"""Summarizes Benchmarks/results/transcription-research/*.json + .log (caption-bench --dump output).

Usage: python3 -I Benchmarks/research/analyze.py [case ...]   (no arguments: every case)
Adds what caption-bench does not report:
- per-sentence final latency (time the final arrived minus the end of its audio range), median and max over all runs;
- character error rate with Python (same normalization as TextMetrics: letters and digits only, no spaces);
- English WER after number canonicalization ("2nd" = "second", "$2.4" = "2.4 dollars", "15%" = "15 percent"),
  so a formatting choice is not counted as a recognition error;
- for long-* cases, WER and sentence latency per block (the same text repeated), to see drift.
"""
import json, os, re, statistics, sys, unicodedata

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
RES = os.path.join(ROOT, "results", "transcription-research")
AUDIO = os.path.join(ROOT, "audio", "research")
LINE = re.compile(r"^\s*([\d.]+)s (\S+) (FINAL |interim) conf=(\S+) range=(\S+) \| ?(.*)$")


def norm_chars(t):
    return [c for c in t.lower() if unicodedata.category(c)[0] in "LN"]


def norm_words(t):
    return "".join(c if unicodedata.category(c)[0] in "LN" else " " for c in t.lower()).split()


def edit(a, b):
    prev = list(range(len(b) + 1))
    for i in range(1, len(a) + 1):
        cur = [i] + [0] * len(b)
        for j in range(1, len(b) + 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] != b[j - 1]))
        prev = cur
    return prev[-1]


def rate(ref, hyp):
    return edit(ref, hyp) / max(1, len(ref))


ORD = {"first": "1", "second": "2", "third": "3", "fourth": "4", "fifth": "5", "sixth": "6", "seventh": "7", "eighth": "8",
       "ninth": "9", "tenth": "10", "twenty-first": "21", "twenty first": "21"}
NUM = {"one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10"}


def canon_en(t):
    t = t.lower()
    t = re.sub(r"\$([\d.,]+)( million| billion| thousand)?", lambda m: m.group(1) + (m.group(2) or "") + " dollars", t)
    t = t.replace("%", " percent")
    t = re.sub(r"(\d+)(st|nd|rd|th)\b", r"\1", t)
    t = re.sub(r"(\d),(\d{3})", r"\1\2", t)
    for k in sorted(ORD, key=len, reverse=True): t = re.sub(rf"\b{k}\b", ORD[k], t)
    for k, v in NUM.items(): t = re.sub(rf"\b{k}\b", v, t)
    t = re.sub(r"(\d)\.(\d)", r"\1point\2", t)  # keep "2.4" as one token through punctuation stripping
    t = re.sub(r"(\d):(\d)", r"\1colon\2", t)
    return norm_words(t)


def parse_log(path):
    """Returns a list of runs; each run is a list of (t, isFinal, start, end, text)."""
    runs, cur = [], []
    for line in open(path, encoding="utf-8", errors="replace"):
        if line.startswith("run "):
            runs.append(cur); cur = []; continue
        m = LINE.match(line)
        if not m: continue
        t, _, kind, _, rng, text = m.groups()
        start = end = None
        if rng != "-":
            a, b = rng.split("-", 1); start, end = float(a), float(b)
        cur.append((float(t), kind.startswith("FINAL"), start, end, text.strip()))
    return runs


def summarize(name):
    d = json.load(open(os.path.join(RES, name + ".json")))
    m = d["median"]
    log = os.path.join(RES, name + ".log")
    runs = parse_log(log) if os.path.exists(log) else []
    stem = open(os.path.join(RES, name + ".stem")).read().strip()
    ref = ref_for(stem)
    out = {"name": name, "locale": d["locale"], "speech": d["speechSeconds"], "first": m.get("firstPartialSeconds"),
           "finalDelay": m.get("finalDelaySeconds"), "wer": m["wer"], "cer": m["cer"], "finals": m["finals"],
           "conf": m.get("meanConfidence"), "rss": m["peakRSSMB"], "cpu": m["cpuPercent"], "startup": m["startupSeconds"],
           "recognized": m["recognized"], "wers": [r["wer"] for r in d["runs"]], "cers": [r["cer"] for r in d["runs"]]}
    lat = [t - e for run in runs for (t, fin, s, e, txt) in run if fin and e is not None and txt]
    if lat:
        out["sentLatMed"] = statistics.median(lat); out["sentLatMax"] = max(lat)
    # The saved transcript stamps a sentence when its final arrives; how far is that from when the sentence was spoken,
    # and how long are the finals (one line in the transcript each)?
    skew = [t - s for run in runs for (t, fin, s, e, txt) in run if fin and s is not None and txt]
    span = [e - s for run in runs for (t, fin, s, e, txt) in run if fin and s is not None and txt]
    if skew:
        out["stampSkewMed"] = statistics.median(skew); out["stampSkewMax"] = max(skew)
        out["finalSpanMed"] = statistics.median(span); out["finalSpanMax"] = max(span)
    if d["locale"].startswith("en"):
        out["werCanon"] = statistics.median(rate(canon_en(ref), canon_en(r["recognized"])) for r in d["runs"])
    out["cerPy"] = statistics.median(rate(norm_chars(ref), norm_chars(r["recognized"])) for r in d["runs"])
    if name.startswith("long"):
        out["blocks"] = blocks(stem, ref, runs, d["locale"])
    return out, d, runs


def blocks(stem, ref, runs, locale, count=6, gap=1.5):
    """Per block of the repeated text: error rate and sentence latency, over all runs."""
    import wave
    with wave.open(os.path.join(AUDIO, stem + ".wav")) as w:
        duration = w.getnframes() / w.getframerate()
    block = (duration - (count - 1) * gap) / count
    words = norm_words(ref)
    ref_block = words[: len(words) // count] if locale.startswith("en") else norm_chars(ref)[: len(norm_chars(ref)) // count]
    result = []
    for b in range(count):
        lo, hi = b * (block + gap) - gap / 2, (b + 1) * (block + gap) - gap / 2
        errs, lats = [], []
        for run in runs:
            finals = [(t, s, e, txt) for (t, fin, s, e, txt) in run if fin and s is not None and txt and lo <= (s + e) / 2 < hi]
            hyp = " ".join(x[3] for x in finals)
            errs.append(rate(ref_block, norm_words(hyp) if locale.startswith("en") else norm_chars(hyp)))
            lats += [t - e for (t, s, e, _) in finals]
        result.append((statistics.median(errs), statistics.median(lats) if lats else None, max(lats) if lats else None))
    return result


def ref_for(stem):
    return open(os.path.join(AUDIO, stem + ".txt"), encoding="utf-8").read().strip()


def main():
    names = sys.argv[1:] or sorted(f[:-5] for f in os.listdir(RES) if f.endswith(".json"))
    for n in names:
        s, d, runs = summarize(n)
        f = lambda v, k=".2f": "n/a" if v is None else format(v, k)
        print(f"{n:28s} first {f(s['first'])}  last-final {f(s['finalDelay'])}  sent-lat med {f(s.get('sentLatMed'))} max {f(s.get('sentLatMax'))}"
              f"  WER {s['wer']*100:.1f}% CER {s['cer']*100:.1f}% (runs WER {[round(w*100,1) for w in s['wers']]} CER {[round(c*100,1) for c in s['cers']]})"
              f"  finals {s['finals']}  conf {f(s['conf'])}  rss {s['rss']:.0f}MB cpu {s['cpu']:.1f}%")
        if "stampSkewMed" in s:
            print(f"    timestamp skew (final arrives - speech start) med {s['stampSkewMed']:.1f} max {s['stampSkewMax']:.1f} s;"
                  f" final length med {s['finalSpanMed']:.1f} max {s['finalSpanMax']:.1f} s; CER(py) {s['cerPy']*100:.1f}%")
        if "werCanon" in s: print(f"    WER after number canonicalization {s['werCanon']*100:.1f}%")
        for i, (err, med, mx) in enumerate(s.get("blocks", [])):
            print(f"    block {i + 1}: error {err*100:.1f}%  sentence latency median {f(med)} max {f(mx)}")
        print(f"    {s['recognized']}")


if __name__ == "__main__":
    main()
