"""Builds Benchmarks/results/<label>.md from the per-case JSON files, optionally with deltas against a baseline."""
import json, os, platform, subprocess, sys

label = sys.argv[1]
baseline = sys.argv[sys.argv.index("--baseline") + 1] if "--baseline" in sys.argv else None
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "results")

def load(name):
    folder = os.path.join(root, name)
    cases = {}
    if os.path.isdir(folder):
        for f in sorted(os.listdir(folder)):
            if f.endswith(".json"):
                d = json.load(open(os.path.join(folder, f)))
                cases[d["name"]] = d
    return cases

def fmt(v, kind="s"):
    if v is None: return "n/a"
    return {"s": f"{v:.2f}", "pct": f"{v*100:.0f}%", "cpu": f"{v:.0f}%", "mb": f"{v:.0f}"}[kind]

def delta(new, old, kind="s", lower_better=True):
    if new is None or old is None: return ""
    d = new - old
    if kind == "pct": text = f"{d*100:+.0f} pt"
    elif kind == "cpu": text = f"{d:+.0f} pt"
    elif kind == "mb": text = f"{d:+.0f}"
    else: text = f"{d:+.2f}"
    if abs(d) < 1e-9: return " (=)"
    better = (d < 0) == lower_better
    return f" ({text} {'better' if better else 'worse'})"

cur, base = load(label), load(baseline) if baseline else {}
git = subprocess.run(["git", "describe", "--tags", "--always", "--dirty"], capture_output=True, text=True).stdout.strip()
lines = [f"# Benchmark: {label}", "",
         f"- Code: `{git}`", f"- Machine: {platform.machine()}, macOS {platform.mac_ver()[0]}",
         "- Input: synthesized speech played into the real engines in real time (clean audio, repeatable; not real-room audio).",
         "- Values are the median of the runs. Times are seconds. Lower is better except where stated.", ""]
if baseline: lines += [f"Compared with baseline `{baseline}`.", ""]
metrics = [
    ("Startup (engine ready)", "startupSeconds", "s"),
    ("First partial after speech start", "firstPartialSeconds", "s"),
    ("Last final after speech end", "finalDelaySeconds", "s"),
    ("Word error rate", "wer", "pct"),
    ("Character error rate", "cer", "pct"),
    ("First translation after speech start", "firstTranslationSeconds", "s"),
    ("Final translation lag", "finalTranslationLagSeconds", "s"),
    ("Interim translation lag", "interimTranslationLagSeconds", "s"),
    ("CPU while running", "cpuPercent", "cpu"),
    ("Peak memory (MB)", "peakRSSMB", "mb"),
]
for name, c in cur.items():
    m, b = c["median"], base.get(name, {}).get("median", {})
    lines += [f"## {name}  ({c['locale']}, {c['engine']}, {c['speechSeconds']:.0f} s of speech, {len(c['runs'])} runs)", "",
              "| Metric | Value |", "|---|---|"]
    for title, key, kind in metrics:
        v = m.get(key)
        if v is None and key in ("firstTranslationSeconds", "finalTranslationLagSeconds", "interimTranslationLagSeconds"): continue
        lines.append(f"| {title} | {fmt(v, kind)}{delta(v, b.get(key), kind) if b else ''} |")
    note = m.get("translationNote")
    if note: lines.append(f"| Translation | unavailable: {note} |")
    lines += ["", f"Recognized: _{m.get('recognized', '')}_", ""]
open(os.path.join(root, f"{label}.md"), "w").write("\n".join(lines))
print(f"wrote Benchmarks/results/{label}.md")
