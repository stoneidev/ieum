# Benchmarks

Method: `Benchmarks/run.sh`. Synthesized speech (macOS voices Samantha, Karen, Yuna) is played into the **real** engines in real
time through `FileAudioCapture`; the median of 3 runs is reported. Machine: Apple Silicon, macOS 26.6.

**What these numbers are not.** Synthesized speech is clean and perfectly paced. Real meeting rooms add noise, distance,
overlapping voices and accents, so absolute accuracy there will be lower. Use the numbers to compare versions, not to promise
accuracy. Recognition quality in a real 3 to 6 person room has **not** been measured.

## v0.1.0 → v0.2.0

| Case | Metric | v0.1.0 | v0.2.0 |
|---|---|---|---|
| Korean (ko-KR) | last sentence final, after speech ends | 2.58 s | **0.85 s** |
| Korean | speech end → last translation | 3.42 s | **2.08 s** |
| English (en-US) | speech end → last translation | 1.73 s | 1.76 s (same, within noise) |
| English (en-AU) | speech end → last translation | 2.28 s | **2.05 s** |
| Terms sample, with the vocabulary list | word error rate | 14% | **4%** |
| Mixed English/Korean conversation | language chosen correctly | not possible | **100%** (every run) |
| Mixed English/Korean conversation | character error rate | 43% (one language only) | **4 to 7%** |
| Mixed English/Korean conversation | last sentence final, after speech ends | n/a | 0.86 s |
| All cases | first word after speech starts | about 1.0 s | about 1.0 s (unchanged) |
| All cases | CPU / memory | 3% / 26 MB | 3% (4% in conversation) / 26 MB (29 MB with a vocabulary list) |

What changed it:
- **Pause finalization** (0.7 s of silence after speech ends the sentence immediately) fixed the slow Korean finals and made the two
  recognizers of conversation mode cut sentences at the same places. The request is sent only if the recognizer still has unfinished
  text, and re-checked 150 ms later, because a request for a sentence the recognizer has just finalized itself makes it end the session.
- A **separate translator for finished sentences** removed the wait behind the interim translation that is always running while someone talks.
- The **vocabulary list** is applied to the text after recognition. Contextual strings given to the recognizer were measured to have
  no effect on the new recognizer and are only used by the compatibility engine. A word that is in the system dictionary is only
  replaced on an exact match, so a term such as "Node" does not rewrite "mode" or "code". The dictionary costs about 7 MB.
- **Conversation arbitration** keeps, per sentence, the recognizer whose text is both confident and written in its own language.
  Weak results wait longer (1.8 s) for a better rival; sure results are shown at once; sentences are always shown in the order spoken.

Known weaker points, measured:
- First translation after speech starts is 0.10 to 0.15 s later for en-AU and ko-KR (the second translator's first call).
- In the mixed conversation sample, the word "Great" at the start of the third turn was lost (`..., that works for me.`).
- Korean word error rate (33%) looks high only because Korean spacing varies; its character error rate is 2%.
- Translation takes about 0.7 to 1.3 s per sentence on this Mac, so on-screen translation trails speech by roughly 1 to 2 s.
- The `mixed-en-only` case ends with a negative "last final" because the English-only recognizer never produces the final Korean turn.

Bugs found by this benchmark while building v0.2.0 (all fixed; kept here because they show what to watch):
the recognizer ending the session after a duplicate finalize request; an English translation slowdown caused by finals queueing behind
interim translations; a duplicate filter that dropped the real Korean sentence after the wrong-language recognizer's noise had been shown;
sentences shown out of order when a sure result overtook a waiting one.

## Not measured

Far-field accuracy in a meeting room, multiple people talking at once, the low-latency translation model (not installed on the test
Mac), long sessions, and full-screen apps.

## Tried and not kept: reusing the interim translation for the final sentence

Idea: when a sentence ends unchanged from the last interim text that was translated, show that translation at once instead of translating again.
Result on this Mac (3 runs per case, against v0.2.0): no gain. Final translation lag was 1.44 s (en-AU, +0.14), 0.87 s (en-US, unchanged) and
1.51 s (ko-KR, +0.28). The interim translation trails speech by 0.75 to 0.9 s, so by the time a sentence is final the text has usually grown by a word
or its punctuation has changed, and the cached translation does not match. The change was removed again.

## Early words: the legacy recognizer shows the sentence being spoken

The modern recognizer reports interim text in bursts about once a second (first words at about 1.0 s). The legacy recognizer streams word by word
(first word at about 0.5 s, then every 0.2 to 0.3 s). With `showsWordsSooner` (bench flag `--early-words`) both run on the same audio; the legacy words
are shown for the sentence being spoken, and every finished sentence still comes from the modern recognizer.
Measured on en-US (9 s of speech, 3 runs): first text 1.01 s to 0.51 s; word error rate 3 % to 3 %; final delay 0.90 s to 0.89 s; CPU 1.3 % to 2.7 %;
peak memory 21.7 MB to 24.1 MB. Needs the Speech Recognition permission; without it captions run as before. Not used in Conversation mode.
Known rough edge: the two recognizers split sentences slightly differently, so a word at a sentence boundary can show up in the previous sentence for a moment.

## Closing sentences at a pause damages the next sentence's first words

Six sentences with a gap between them (synthesized speech, the pause rule set to 0.7 s). With the pause rule the first words of most sentences
after a gap came out as `be... I am`, `. of a little bit`, `.........`, `. we, named it`: word error rate 20 % at 0.85 s gaps, 18 % at 1.2 s, 15 % at 2.0 s.
Without it: 6 %, 8 %, 7 %. Placing the boundary earlier (0.3 s or 0.5 s pause, or at the end of speech) did not help, so the damage comes from asking the
recognizer to finalize, not from where. The recognizer's own finalization closes English sentences about 0.9 s after speech ends (4.92 s against 4.19 s for a
sentence ending at 4.0 s), so English single-language modes no longer use the pause rule.

It stays on where it is needed: Korean (final delay 0.84 s with it, 2.59 s without) and the auto-detect mode (word error rate 10 % with it, 29 % without;
language chosen correctly 100 % against 50 %; final delay 0.85 s against 2.61 s). In those modes English sentences after a pause can still lose their first
words; a way to keep the speed without the damage is not found yet.
Bench flags for this: `--pause <seconds>`, `--no-pause-finalization`, `--no-fast`, `--no-vad`.

## Meeting-notes prompt (`minutes-eval`)

The minutes, lecture notes and conversation summaries are written by the on-device model (Foundation Models) from `MinutesPrompt` (the instructions,
in the language of the notes) plus the `Draft` schema in `MinutesWriter`, and then cleaned the same way every time (`MeetingMinutes.validated`, `grounded`).
Changing any of that is measured with `swift build -c release --product minutes-eval && .build/release/minutes-eval Benchmarks/minutes --runs 2`
(about 6 minutes; needs Apple Intelligence). It writes the notes for 8 transcripts with an answer key (`Benchmarks/minutes/*.json`: Korean and English
meetings with proposals, pending matters and negations, a Korean notes version of an English meeting, two talks, a conversation) and scores: recall of the
expected facts, whether a found fact cites a line where it is said (`cited`), the right person and day on tasks (`owner`, `due`), pending matters or proposals
written as decisions (`forbidden`, lower is better) and items that are in no answer key (`unlisted`, mostly invented).

Baseline, the first version of the instructions (a short list of rules, with an example whose names and day were copied into other meetings), same Mac, 2 runs:

| | recall | cited | owner | due | forbidden | unlisted |
|---|---|---|---|---|---|
| first instructions (6 of 8 fixtures; **both talks failed outright**) | 74 % | 100 % | 100 % | 88 % | 2 | 20 |
| rewritten instructions + clean-up (9 fixtures, after review fixes) | 78 % | 95 % | 89 % | 91 % | 2 | 36 |

Read with care: the answer keys of three fixtures were corrected after the baseline run, the baseline did not complete the two talks, a ninth fixture (two
meetings in one long record, read in several parts) was added and is the weakest (recall 60 %), and `unlisted` grew because the two talks (about 10 key points
each) now count. Before the ninth fixture, the same eight scored recall 83 %, cited 94 %, owner 86 %, due 89 %. What the runs showed, and what was done about it:

- **Both talks failed** ("May contain unsafe content" for a Korean talk about privacy, "sensitive content" for an English one about failed projects): the default
  guardrails refuse ordinary text. Now the session uses `.permissiveContentTransformations`, and a part the model still declines is read as two halves; one line it
  declines is left out instead of failing the whole notes.
- **The example leaked.** A task had the owner "민수" and the day "수요일" in a conversation where nobody said either, a question was "릴리스 노트 업데이트…": all from
  the example. The new example is about something unrelated (an offsite, bees), says so, and `grounded` drops an owner or a day that does not occur in the transcript.
- **A negative rule was copied** ("do not write 'someone said'" produced the owner "누군가 말했다"). The rules are now positive ("write it as a secretary would").
- **Invented items had no source line.** Of the questions the model made up for an English talk, 5 of 7 cited no line (nobody asked them). Points that cite no
  existing line are dropped now (`unlisted` 66 → 34 and `forbidden` 6 → 2 with this and the next two changes).
- **Assigned tasks also appeared as decisions** ("금요일까지 테스트 환경 준비"): same-meaning points are removed across lists (task, then decision, key point, question),
  and a "decision" that says the matter is open ("아직 결정되지 않음", "cannot decide") is moved to the open questions.
- A task text repeated its owner ("Priya — Priya will fix…"): the owner is stripped from the front of the text, only when the name stands alone (an independent
  review found it turned "Annual review" into "ual review" and "민수 이사에게" into "사에게"; fixed and tested).
- Review fixes found by reading, not by the eval: two tasks with the same words for two people were merged into one, a point with no source shadowed a later good
  one, "on hold"/"보류" in a real decision sent it to the questions, two different dates were merged as duplicates, a line the model refuses is no longer dropped
  silently (the notes say which lines were not read), and a single over-long line is cut and read instead of failing the notes.

Tried and not kept: telling the model that the owner is "the person called by name" (e.g. "Lena, please send it": Lena). Recall 83 % → 78 %, cited 94 % → 88 %, unlisted 34 → 42.
Still weak, because the model is small: assigned tasks without a name in the sentence ("누가 보내죠? 지수 씨가…" across two lines), a task nobody names, "X 하기로 결정됨"
wording on tasks, and a summary that sometimes calls a talk a meeting. Every item carries its source lines for exactly this reason.
