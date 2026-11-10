# Transcription research (2026-11-11)

What would most improve the transcript (recognition side, not translation) for people using Ieum in meetings. Measured on this Mac
(Apple Silicon, macOS 26.6, lid closed), with `caption-bench` playing files in real time into the real engines, at the code on `main`.

**Limits.** All input is `say` speech. Noise, reverb and babble are synthetic (numpy). Each case is one short passage, 2 runs (3 for ja/zh);
runs were nearly identical, so the numbers are repeatable but say nothing about variety of speakers. Real-room accuracy is still unmeasured.
CPU/memory are the bench process only; the speech work runs in a system daemon, so its cost is **not** in these numbers.

Reproduce: `python3 -I Benchmarks/research/make_audio.py` (audio to `Benchmarks/audio/research`, ignored), then
`Benchmarks/research/run.sh 2 @Benchmarks/research/cases-quality.txt` (also `cases-levers.txt`, `cases-followup.txt`; single cases are
`name:locale:stem[:flag+flag]`), then `python3 -I Benchmarks/research/analyze.py [case...]`. Raw JSON and `--dump` logs:
`Benchmarks/results/transcription-research/`. English cases run with `--no-pause-finalization` (as the app's English modes do; the bench
default is on), Korean/Japanese/Chinese with the default 0.7 s pause rule.

Metrics added by `analyze.py`: **sentence latency** (final arrives minus end of its audio range), **timestamp skew** (final arrives minus
start of its speech: how late the saved transcript's `[HH:mm:ss]` is), **final length** (seconds of speech per final = per transcript line),
**WER after number canonicalization** (`2nd` = `second`, `$2.4 million` = `2.4 million dollars`, `15%` = `15 percent`), CER for ja/zh.

## Ranked recommendation

| # | Build | Evidence | Expected gain |
|---|---|---|---|
| 1 | **Shorter pause rule for Korean (and ja/zh): 0.7 s → 0.4 s** | Korean is not split into sentences by the recognizer itself (English is). 60 s Korean block, 0.6 s between sentences: 0.7 s → 5 finals of 14 s; 0.4 s → 15 finals (one per sentence). CER 2.5 % → 2.8 %. 1.2 s gaps: last final 0.84 → 0.54 s (ko), 0.86 → 0.59 (ja), 0.84 → 0.55 (zh), CER unchanged (0 / 2.3 / 0 %). 1.0 s was worse (CER 3.1 %, 1.14 s) | Finals (and so ko→en translations and transcript lines) per sentence instead of every ~14 s; about 0.3 s faster finals. Risk: hesitations inside a sentence split it. **Needs a real-speech check** before shipping |
| 2 | **Transcript time = when the sentence was spoken** (session start + `audioStart`), and one line per sentence | Timestamp skew today: en 4.6 s median, ko 11–15 s, long ko session 14.8 s (max 17 s), ja 18.8 s (one 18 s final). Korean finals hold 3–4 sentences per line | Skew → ~0 s; transcript lines readable and searchable. Pure CaptionCore change (testable), no recognizer risk |
| 3 | **Safety net for text dropped by fast results** | Korean with English terms (`codeswitch-ko`): interim text stops growing at 12.5 s while speech goes on to 15 s; the final loses the last 1.5 sentences (CER 47 %) in every run, with/without VAD, pause rule, vocabulary or lead-in. `--no-fast` keeps everything (CER 24 %, the rest is transliteration). Reproduced outside Ieum (`Benchmarks/research/dual.swift single`). A **second, separate analyzer** without fast results on the same audio (`dual.swift two`) kept the fast one's first text at 1.04 s and delivered the complete final 2.3 s after the fast one. Two transcribers in **one** analyzer delay everything to the slow one's pace (first text 11.5 s): not usable | Prevents silent loss of whole sentences. How often it happens on real speech is unknown (seen only in the code-switching passage, in every variant of it; not in the other Korean passages or the 6-min sessions): first add a cheap detector (fast final ends while the audio still has speech) and log it, then decide on the second analyzer. System CPU cost of a second analyzer **not measured** |

Also worth doing, small: count numbers fairly in `TextMetrics`/`report.py`. The headline "en-US WER 3 %" is one formatting difference
(`2nd` for `second`); after canonicalization it is 0 %. Same for `numbers-en` (13.3 % → 4.7 %).

## Results by area

### a. Harder input

| Case | English (WER canon.) | Korean (CER) |
|---|---|---|
| Clean (0.5 s lead-in) | 0 % | 1.8 % |
| Fast speech 250 / 320 wpm (`say -r`) | 0 % / 0 % | 5.4 % / 8.9 % |
| Pink noise SNR 20 / 10 / 5 dB | 0 / 6.9 / 6.9 % | 1.8 / 1.8 / 5.4 % |
| Babble (4 voices) SNR 15 / 10 / 5 dB | 0 / 0 / 6.9 % | 1.8 / 1.8 / 14.3 % |
| Quiet (−30 dB) | 0 % | 1.8 % |
| Reverb (RT60 0.7 s) | 0 % | **8.9 %** |
| Reverb + pink noise 10 dB | 6.9 % | **28.6 %** |
| Numbers, dates, amounts | 4.7 % (13.3 % raw) | 4.2 % (2.8 % with lead-in) |
| Korean with English terms | – | 47 % (tail dropped, see #3) |

- English is robust to noise down to 10 dB and to 320 wpm. Korean is the weak side: far-field (reverb) hurts it most. This is the biggest
  accuracy risk for in-room use and **needs real-room data**; nothing here can fix it (system voice processing is microphone-only, not testable from a file).
- Numbers are recognized well; formatting is mostly good (`$2.4 million`, `15%`, `June 21, 2026`, `3월 3일 오전 9시 30분`, `204호`).
  Errors: `9.30` for 9:30; `7731은` → `7730일은` (homophone 삼십일); `2억 4천만` → `2억 4천백` only when speech starts at sample 0.
- Code-switching: `API`, `AWS`, `PR` come out in Latin letters; `Kubernetes` → `큐버닉스`, `Figma` → `피그마/피로`, `Slack` → `슬랙`.
  `--vocabulary API,AWS,Kubernetes,Figma,PR,Slack` changed nothing (47.4 % → 47.4 %): `VocabularyCorrector` does not map Hangul transliterations to Latin terms.
  A Hangul-transliteration alias list (`큐버닉스`/`쿠버네티스` → Kubernetes) would be the cheap fix; not built or measured.
- Words at the very first instant of a session are lost: `numbers-en` without lead-in starts "budget for the…" (WER 13.3 %), with 0.5 s
  lead-in "The budget…" (6.7 %). Matters after restarts (mode switch, auto-restart) while someone is talking; not measured in the app.
- Long sessions (6 min, the same 15-sentence block 6 times): **no drift**. English per-block WER 1.7 / 2.3 / 0.6 / 1.7 / 2.3 / 2.9 %,
  sentence latency median 0.72–0.88 s, max 1.12 s; Korean per-block CER 2.5 / 1.9 / 1.6 / 2.5 / 2.2 / 1.9 %. Peak memory 24 MB, CPU 1.6–1.8 %.

### b. Punctuation, casing, numbers in the final text

| Language | Sentence ends kept (ref → hyp) | Notes |
|---|---|---|
| English | 3/3, 90/90 in 6 min | Casing correct; commas 35/36 |
| Korean | 15/15, 90/90; first `안녕하세요` lacks a period | Spacing differs (`확인해주세요`), the cause of the "33 % WER" |
| Japanese | 6/6 | `第二4半期` (mixed numerals) once |
| Chinese | **2/6** on the gap sample, 2/3 continuous; stray space before `，` | Cheap fix for zh: add `。` to a final without end punctuation, drop the space before full-width punctuation |

The legacy recognizer formats numbers a little better in English (`9:30`, `7731`, `March 3`, WER canon. 0 %), worse in Korean
(`200,004,000 만원`, CER 25 %), and splits Korean words with spaces. Not a reason to switch engines.

On-device language model polish (`FinalTextPolisher` instructions, `Benchmarks/research/polish.swift`, 11 recognized sentences): **0 of 11**
would pass `PolishGuard`. It translated Korean/Chinese/Japanese into English, answered sentences as requests ("Sure, I can help you with that…"),
invented a year ("March 3, 2024"), and changed "9.30 in the morning" to "9:30 AM". 7 s per sentence cold, 0.7–2.3 s warm. Not worth it.

### c. Latency levers

| Lever | Result | Verdict |
|---|---|---|
| `--no-fast` | First text 0.51 → 7.2 s (en), 0.54 → 11.2 s (ko); accuracy mixed (Korean reverb 8.9 → 5.4 %, babble 5 dB 14.3 → 16.1 %, pink 5 dB 5.4 → 8.9 %; English reverb+noise 6.9 → 13.8 %) | Not worth it alone; only as the second analyzer of #3 |
| `--no-vad` | No change (en 0.52 s / 3.4 %; ko 0.54 s / 1.8 %, but last final 0.95 → 3.07 s and an extra `.` final) | Not worth it |
| `--early-words` for Korean | 0.54 → 0.54 s on the clean passage (same CER, memory +2 MB): with 0.5 s lead-in the modern recognizer is already at 0.54 s, so this sample cannot show the gain (English showed 1.01 → 0.51 s without lead-in) | Inconclusive here; re-measure on a no-lead-in Korean file |
| `--early-words` for ja/zh | No effect: the legacy recognizer has no on-device ja-JP/zh-CN model here (`--legacy` errors "No Assistant asset") | Not available unless Dictation for that language is installed (untested) |
| Pause 0.4 s (ko/ja/zh) | See #1 | Worth building, check on real speech |
| Pause 1.0 s (ko) | Slower (1.14 s) and CER 3.1 % | Not worth it |
| Lead-in phase | First text is 0.51 s when there is 0.5 s of silence before speech, 1.02 s when speech starts at sample 0: results come in ~1 s audio bursts, so the "1.0 s first word" in BENCHMARKS.md depends on where speech falls in the burst | Measurement note; real average is between the two |

### d. Japanese and Chinese (SpeechTranscriber, 3 runs; models downloaded in seconds on first run)

| Case | First text | Last final after speech | CER | Finals |
|---|---|---|---|---|
| ja-JP continuous (18 s), pause rule 0.7 s | 0.97 s | 0.84 s | 1.1 % | 1 |
| ja-JP continuous, `--no-pause-finalization` | 0.97 s | 1.29 s | 1.1 % | 1 |
| ja-JP 6 sentences, 1.2 s gaps, 0.7 s | 0.97 s | 0.86 s | 2.3 % | 6 |
| ja-JP gaps, `--no-pause-finalization` | 0.98 s | 2.60 s | 2.3 % | 2 |
| ja-JP gaps, pause 0.4 s | 0.97 s | 0.59 s | 2.3 % | 6 |
| zh-CN continuous (13 s), 0.7 s | 1.06 s | 0.88 s | 0.0 % | 1 |
| zh-CN continuous, `--no-pause-finalization` | 1.02 s | 2.58 s | 0.0 % | 1 |
| zh-CN gaps, 0.7 s | 1.02 s | 0.84 s | 0.0 % | 6 |
| zh-CN gaps, `--no-pause-finalization` | 1.06 s | 1.54 s | 0.0 % | 2 |
| zh-CN gaps, pause 0.4 s | 1.07 s | 0.55 s | 0.0 % | 6 |
| ko-KR gaps (control), 0.7 s / none | 1.05 s | 0.84 / 1.02 s | 0 / 0 % | 6 / 2 |

Japanese and Chinese behave like Korean: the pause rule does **not** damage them (CER identical with and without) and is needed for
speed (0.84 s vs 1.3–2.6 s) and for one final per sentence. Treat them as Korean in the multi-language refactor (pause rule on, 0.4 s
candidate). Without the rule, sentences are merged into 12 s finals. Reference texts: `Benchmarks/research/refs/{ja-JP,zh-CN,gaps-*}.txt`.
WER is meaningless for these languages (50–80 % only because there are no spaces).

### e. Transcript output

- Timestamps are arrival times (see #2). Skew grows with final length, so Korean/Japanese lines are stamped 11–19 s late.
- One line per final: Korean lines carry 3–4 sentences (14 s) at the 0.7 s rule, English lines one sentence (3.6–4.2 s).
- Speaker cues: not measurable with this setup (needs diarization, which the Speech framework does not offer on device). Not evaluated.

## Tried and not kept

- On-device LLM polish of finals: 0/11 accepted by the guard; translates, answers, invents dates; 0.7–2.3 s warm, 7 s cold.
- Turning fast results off: first text 7–11 s; accuracy better in 2 of 6 noisy cases, worse in 4.
- Two transcribers in one SpeechAnalyzer (fast + not fast): the analyzer runs at the slow one's pace (first text 11.5 s for both).
- VAD off: no accuracy change; one slower final (3.07 s) in Korean.
- Pause rule 1.0 s for Korean: slower and less accurate than 0.7 or 0.4 s.
- Vocabulary list for English terms spoken in Korean: no effect (47.4 % → 47.4 %), the recognizer writes them in Hangul.
- Legacy recognizer for better number formatting: better English numbers, much worse Korean (CER 25 %); not available for ja/zh here.
