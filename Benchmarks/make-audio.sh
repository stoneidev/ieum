#!/bin/zsh
# Generates the benchmark audio from the reference texts with the macOS speech synthesizer.
# Synthesized speech is clean and repeatable, so results are comparable between versions. It is NOT a stand-in
# for real meeting audio: absolute accuracy on real rooms will be lower.
set -e
cd "$(dirname "$0")"
mkdir -p audio
gen() { # name voice
  [ -f "audio/$1.wav" ] || say -v "$2" -o "audio/$1.wav" --data-format=LEI16@22050 -f "refs/$1.txt"
}
gen en-US Samantha
gen en-AU Karen
gen ko-KR Yuna
gen terms-en-US Samantha
echo "audio ready in Benchmarks/audio"
