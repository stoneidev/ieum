#!/bin/zsh
# Usage: Benchmarks/run.sh <label> [runs]
# Runs every case through ieum-bench and writes Benchmarks/results/<label>.md (+ raw JSON next to it).
set -e
cd "$(dirname "$0")/.."
LABEL=${1:?label required}
RUNS=${2:-3}
BIN=.build/release/ieum-bench
[ -x $BIN ] || { echo "Build first: swift build -c release --product ieum-bench"; exit 1; }
Benchmarks/make-audio.sh
OUT=Benchmarks/results/$LABEL
rm -rf $OUT; mkdir -p $OUT
run() { # name locale file-stem translate-to [extra args]
  local name=$1 locale=$2 stem=$3 target=$4; shift 4
  local args=(--name "$name" --locale $locale --file Benchmarks/audio/$stem.wav --reference-file Benchmarks/refs/$stem.txt --runs $RUNS --output $OUT/$name.json)
  [ -n "$target" ] && args+=(--translate-to $target)
  echo "== $name"; $BIN "${args[@]}" "$@"
}
run en-US en-US en-US ko
run en-AU en-AU en-AU ko
run ko-KR ko-KR ko-KR en
run terms-en-US en-US terms-en-US ""
run terms-en-US-vocab en-US terms-en-US "" --vocabulary "Kubernetes,Terraform,Grafana,Priya,Siobhan,OKR,Figma,Jira,Azure"
echo "== conversation (mixed en/ko)"
$BIN --name conversation-mixed --locale en-US --conversation --expected-languages en,ko,en,ko \
  --file Benchmarks/audio/mixed.wav --reference-file Benchmarks/refs/mixed.txt --runs $RUNS --output $OUT/conversation-mixed.json
echo "== single-language engine on the same mixed audio (what the user had before)"
$BIN --name mixed-en-only --locale en-US --file Benchmarks/audio/mixed.wav --reference-file Benchmarks/refs/mixed.txt --runs $RUNS --output $OUT/mixed-en-only.json
report=(Benchmarks/report.py $LABEL)
[ -n "$BASELINE" ] && report+=(--baseline "$BASELINE")
python3 -I "${report[@]}"
