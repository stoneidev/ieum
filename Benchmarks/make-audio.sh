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
# Alternating English / Korean turns, like a conversation between a Korean speaker and a native speaker.
if [ ! -f audio/mixed.wav ]; then
  say -v Samantha -o audio/mixed-1.wav --data-format=LEI16@22050 "Could you share the schedule for next week?"
  say -v Yuna     -o audio/mixed-2.wav --data-format=LEI16@22050 "네, 공유해 드리겠습니다. 다음 주 월요일부터 시작합니다."
  say -v Samantha -o audio/mixed-3.wav --data-format=LEI16@22050 "Great, that works for me. What about the budget?"
  say -v Yuna     -o audio/mixed-4.wav --data-format=LEI16@22050 "예산은 아직 검토 중입니다. 내일까지 알려 드리겠습니다."
  python3 -I - <<'PY'
import wave
parts = [f"audio/mixed-{i}.wav" for i in range(1, 5)]
out = wave.open("audio/mixed.wav", "wb")
for i, p in enumerate(parts):
    w = wave.open(p, "rb")
    if i == 0:
        out.setparams(w.getparams())
    out.writeframes(w.readframes(w.getnframes()))
    if i < len(parts) - 1:  # 1.2 s of silence between turns
        out.writeframes(b"\x00\x00" * int(w.getframerate() * 1.2))
    w.close()
out.close()
PY
  rm -f audio/mixed-[1-4].wav
fi
echo "audio ready in Benchmarks/audio"
