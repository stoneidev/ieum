# Benchmark: baseline-v0.1.0

- Code: `v0.1.0-dirty`
- Machine: arm64, macOS 26.6.2
- Input: synthesized speech played into the real engines in real time (clean audio, repeatable; not real-room audio).
- Values are the median of the runs. Times are seconds. Lower is better except where stated.

## en-AU  (en-AU, SpeechAnalyzer / SpeechTranscriber, 11 s of speech, 3 runs)

| Metric | Value |
|---|---|
| Startup (engine ready) | 0.07 |
| First partial after speech start | 1.04 |
| Last final after speech end | 0.74 |
| Word error rate | 0% |
| Character error rate | 0% |
| First translation after speech start | 1.25 |
| Final translation lag | 1.54 |
| Interim translation lag | 0.78 |
| CPU while running | 3% |
| Peak memory (MB) | 26 |

Recognized: _Good morning everyone. We have a lot to get through before lunch, so let us start with the sales figures from Melbourne. After that, I would like to hear your thoughts on the new customer onboarding process._

## en-US  (en-US, SpeechAnalyzer / SpeechTranscriber, 9 s of speech, 3 runs)

| Metric | Value |
|---|---|
| Startup (engine ready) | 0.08 |
| First partial after speech start | 1.01 |
| Last final after speech end | 0.93 |
| Word error rate | 3% |
| Character error rate | 3% |
| First translation after speech start | 1.75 |
| Final translation lag | 0.81 |
| Interim translation lag | 0.77 |
| CPU while running | 3% |
| Peak memory (MB) | 26 |

Recognized: _Thanks for joining the call. Today we will review the quarterly budget and the product roadmap. Please open the shared spreadsheet and check the numbers for the 2nd quarter._

## ko-KR  (ko-KR, SpeechAnalyzer / SpeechTranscriber, 10 s of speech, 3 runs)

| Metric | Value |
|---|---|
| Startup (engine ready) | 0.06 |
| First partial after speech start | 1.04 |
| Last final after speech end | 2.58 |
| Word error rate | 33% |
| Character error rate | 2% |
| First translation after speech start | 1.14 |
| Final translation lag | 0.84 |
| Interim translation lag | 0.80 |
| CPU while running | 3% |
| Peak memory (MB) | 25 |

Recognized: _안녕하세요 오늘 회의에서는 분기별 예산과 제품 로드맵을 검토하겠습니다. 공유된 스프레드 시트를 열어서 2분기 숫자를 확인해주세요._

## terms-en-US-vocab  (en-US, SpeechAnalyzer / SpeechTranscriber, 10 s of speech, 3 runs)

| Metric | Value |
|---|---|
| Startup (engine ready) | 0.06 |
| First partial after speech start | 1.04 |
| Last final after speech end | 1.52 |
| Word error rate | 14% |
| Character error rate | 4% |
| CPU while running | 1% |
| Peak memory (MB) | 22 |

Recognized: _R. Q. Bernates cluster on Azure uses terraform and Grafana dashboards. Priya and Siobhan will present the OKR review. Then we discuss the figma handoff and the Jera backlog._

## terms-en-US  (en-US, SpeechAnalyzer / SpeechTranscriber, 10 s of speech, 3 runs)

| Metric | Value |
|---|---|
| Startup (engine ready) | 0.06 |
| First partial after speech start | 1.03 |
| Last final after speech end | 1.52 |
| Word error rate | 14% |
| Character error rate | 4% |
| CPU while running | 1% |
| Peak memory (MB) | 22 |

Recognized: _R. Q. Bernates cluster on Azure uses terraform and Grafana dashboards. Priya and Siobhan will present the OKR review. Then we discuss the figma handoff and the Jera backlog._
