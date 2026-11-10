"""Generates the transcription-research audio into Benchmarks/audio/research (ignored by git).

Usage: python3 -I Benchmarks/research/make_audio.py
Everything is synthesized with macOS `say` (22.05 kHz mono, 16 bit) and post-processed with numpy:
sentence gaps, faster speaking rates, noise beds at a given SNR, a quiet level, a synthetic room reverb,
and long sessions (one block of meeting sentences repeated) so drift over time can be compared block by block.
"""
import os, subprocess, sys, wave
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REFS = os.path.join(HERE, "refs")
BASE_REFS = os.path.join(HERE, "..", "refs")
OUT = os.path.join(HERE, "..", "audio", "research")
RATE = 22050
os.makedirs(OUT, exist_ok=True)


def say(voice, text, rate=None):
    path = os.path.join(OUT, "_clip.wav")
    args = ["say", "-v", voice, "-o", path, "--data-format=LEI16@22050"]
    if rate: args += ["-r", str(rate)]
    subprocess.run(args + [text], check=True)
    return read(path)


def read(path):
    with wave.open(path, "rb") as w:
        assert w.getframerate() == RATE and w.getnchannels() == 1
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64)


def write(name, samples):
    path = os.path.join(OUT, name + ".wav")
    clipped = np.clip(samples, -32768, 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(clipped.tobytes())
    print(f"{name}.wav  {len(samples) / RATE:.1f} s")


def lines(path):
    return [l.strip() for l in open(path, encoding="utf-8") if l.strip()]


def joined(voice, sentences, gap, rate=None):
    parts = []
    for i, s in enumerate(sentences):
        parts.append(say(voice, s, rate))
        if i < len(sentences) - 1: parts.append(np.zeros(int(RATE * gap)))
    return np.concatenate(parts)


def active_rms(x):
    """RMS over the 20 ms windows that hold speech, so silence does not dilute the SNR."""
    w = int(RATE * 0.02)
    frames = x[: len(x) // w * w].reshape(-1, w)
    rms = np.sqrt((frames ** 2).mean(axis=1))
    return np.sqrt((rms[rms > 50] ** 2).mean())


def pink(n, seed=1):
    rng = np.random.default_rng(seed)
    spectrum = np.fft.rfft(rng.standard_normal(n))
    f = np.arange(len(spectrum)); f[0] = 1
    return np.fft.irfft(spectrum / np.sqrt(f), n)


def babble(n, text):
    """Four other voices talking at once, offset in time: the closest thing to a busy room that `say` can make."""
    mix = np.zeros(n)
    for k, voice in enumerate(["Daniel", "Karen", "Moira", "Rishi"]):
        b = say(voice, text)
        b = np.roll(np.resize(b, n), k * RATE * 3)
        mix += b / (active_rms(b) or 1)
    return mix


def with_noise(x, noise, snr_db):
    noise = noise[: len(x)]
    gain = active_rms(x) / (np.sqrt((noise ** 2).mean()) * 10 ** (snr_db / 20))
    return x + noise * gain


def reverb(x, rt60=0.7, direct=0.5):
    """Exponentially decaying noise as a room impulse response (far-field microphone stand-in)."""
    n = int(RATE * rt60 * 1.2)
    rng = np.random.default_rng(7)
    ir = rng.standard_normal(n) * np.exp(-6.9 * np.arange(n) / (RATE * rt60))
    ir[0] = 0; ir /= np.sqrt((ir ** 2).sum())
    wet = np.fft.irfft(np.fft.rfft(x, len(x) + n) * np.fft.rfft(ir, len(x) + n))[: len(x)]
    y = direct * x + wet * (active_rms(x) / (active_rms(wet) or 1))
    return y * (active_rms(x) / active_rms(y))


def ref_out(name, text):
    open(os.path.join(OUT, name + ".txt"), "w", encoding="utf-8").write(text.strip() + "\n")


base = {
    "en-US": ("Samantha", open(os.path.join(BASE_REFS, "en-US.txt")).read().strip()),
    "ko-KR": ("Yuna", open(os.path.join(BASE_REFS, "ko-KR.txt")).read().strip()),
}

# Faster speech. `say` defaults to about 175-190 words per minute; fast talkers reach 250+.
for loc, (voice, text) in base.items():
    for rate in (250, 320):
        write(f"fast{rate}-{loc}", say(voice, text, rate)); ref_out(f"fast{rate}-{loc}", text)

# Numbers, code-switching, Japanese and Chinese (continuous).
for name, voice in [("numbers-en-US", "Samantha"), ("numbers-ko-KR", "Yuna"), ("codeswitch-ko-KR", "Yuna"),
                    ("ja-JP", "Kyoko"), ("zh-CN", "Tingting")]:
    text = open(os.path.join(REFS, name + ".txt"), encoding="utf-8").read().strip()
    write(name, say(voice, text)); ref_out(name, text)
    # Same with 0.5 s of silence first: a word spoken at the very first instant of a session is often lost.
    write("pad-" + name, np.concatenate([np.zeros(RATE // 2), read(os.path.join(OUT, name + ".wav"))])); ref_out("pad-" + name, text)

# Sentences with 1.2 s gaps (where pause finalization acts).
for loc, voice in [("ja-JP", "Kyoko"), ("zh-CN", "Tingting"), ("ko-KR", "Yuna")]:
    s = lines(os.path.join(REFS, f"gaps-{loc}.txt"))
    write(f"gaps-{loc}", joined(voice, s, 1.2)); ref_out(f"gaps-{loc}", " ".join(s))

# Noise, quiet, reverb on the base clips.
long_en = " ".join(lines(os.path.join(REFS, "long-block-en-US.txt")))
for loc, (voice, text) in base.items():
    x = say(voice, text)
    pad = np.zeros(int(RATE * 0.5)); x = np.concatenate([pad, x, pad])
    write(f"clean-{loc}", x); ref_out(f"clean-{loc}", text)
    for snr in (20, 10, 5):
        write(f"pink{snr}-{loc}", with_noise(x, pink(len(x)), snr)); ref_out(f"pink{snr}-{loc}", text)
    bab = babble(len(x), long_en)
    for snr in (15, 10, 5):
        write(f"babble{snr}-{loc}", with_noise(x, bab, snr)); ref_out(f"babble{snr}-{loc}", text)
    write(f"quiet30-{loc}", x * 10 ** (-30 / 20)); ref_out(f"quiet30-{loc}", text)
    write(f"reverb-{loc}", reverb(x)); ref_out(f"reverb-{loc}", text)
    write(f"reverb-pink10-{loc}", with_noise(reverb(x), pink(len(x), 3), 10)); ref_out(f"reverb-pink10-{loc}", text)

# Long sessions: the same 15-sentence block six times (0.6 s between sentences, 1.5 s between blocks).
for loc, voice in [("en-US", "Samantha"), ("ko-KR", "Yuna")]:
    s = lines(os.path.join(REFS, f"long-block-{loc}.txt"))
    block = joined(voice, s, 0.6)
    gap = np.zeros(int(RATE * 1.5))
    write(f"long-{loc}", np.concatenate([block, gap] * 5 + [block])); ref_out(f"long-{loc}", " ".join(s * 6))

os.remove(os.path.join(OUT, "_clip.wav"))
