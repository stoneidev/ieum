#!/bin/zsh
# Usage: Benchmarks/research/run.sh <runs> <case>...   (cases: name:locale:stem[:extra flags separated by +])
# Runs caption-bench per case; writes Benchmarks/results/transcription-research/<name>.json and <name>.log (every event, --dump).
# Example: Benchmarks/research/run.sh 2 ja:ja-JP:ja-JP ja-nopf:ja-JP:ja-JP:--no-pause-finalization
set -e
cd "$(dirname "$0")/../.."
RUNS=${1:?runs}; shift
# "@file" reads the cases from a file, one per line (# starts a comment).
if [[ $1 == @* ]]; then set -- ${(f)"$(grep -v '^#' ${1#@})"}; fi
BIN=.build/release/caption-bench
AUDIO=Benchmarks/audio/research
OUT=Benchmarks/results/transcription-research
mkdir -p $OUT
for spec in "$@"; do
  parts=("${(@s/:/)spec}")
  name=$parts[1] locale=$parts[2] stem=$parts[3]
  extra=()
  [ -n "$parts[4]" ] && extra=("${(@s/+/)parts[4]}")
  echo "== $name ($locale, $stem, $extra)"
  echo $stem > $OUT/$name.stem
  $BIN --name "$name" --locale $locale --file $AUDIO/$stem.wav --reference-file $AUDIO/$stem.txt \
    --runs $RUNS --dump --output $OUT/$name.json "${extra[@]}" 2> $OUT/$name.log
  grep '^run ' $OUT/$name.log
done
