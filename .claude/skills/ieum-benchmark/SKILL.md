---
name: ieum-benchmark
description: Measure recognition latency, accuracy and translation lag of Ieum with synthesized speech, compare against a baseline, and record findings. Use before and after any engine, timing or pipeline change.
---

# Benchmarking Ieum

The harness plays synthesized speech (macOS `say`) into the real engines in real time and reports first-text time, final delay, word/character error rate,
translation lag, CPU and memory. It is repeatable but clean; real rooms will be worse. Say so when reporting.

```sh
make bench LABEL=v0.2.6-x BASELINE=v0.2.0    # whole suite -> Benchmarks/results/v0.2.6-x.md (+ JSON), compared with a baseline
swift build -c release --arch arm64 --product caption-bench
.build/release/caption-bench --locale en-US --file Benchmarks/audio/en-US.wav --reference-file Benchmarks/refs/en-US.txt --runs 3 --dump
```
`--dump` prints every recognizer event with its time (this is how burst vs word-by-word reporting was seen). Useful flags:
`--translate-to ko|en`, `--conversation --expected-languages en,ko,en,ko`, `--early-words`, `--legacy`, `--no-fast`, `--no-vad`,
`--pause <s>`, `--no-pause-finalization`, `--vocabulary a,b`, `--tail <s>`.

To test something specific, generate audio for it: `say -v Samantha -r 200 -o x.wav --data-format=LEI16@22050 "…"` and join clips with gaps using Python's `wave`
(a gap file with 0.85 / 1.2 / 2.0 s silences found the pause-finalization damage). Put a reference text next to it.

Rules: run each variant at least twice; change one thing at a time; keep the numbers (before → after) in `docs/BENCHMARKS.md`, also for ideas that did not help
(section "Tried and not kept"), and revert code that did not earn its place. Results folders are named by version label; `Benchmarks/audio` is generated and ignored.
