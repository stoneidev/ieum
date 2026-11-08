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
