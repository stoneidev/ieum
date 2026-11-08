# Deep Interview Spec: mac-stt Live Subtitle Overlay (macOS menu-bar app)

## Metadata
- Rounds: 6 (Round 0 topology + 6 scored rounds)
- Final Ambiguity Score: ~13% after Round 8 (scores are the interviewer's estimates, not measured)
- Type: brownfield (extends /Users/stoni/Projects/stt)
- Threshold: 0.2
- Threshold Source: default
- Initial Context Summarized: no
- Status: PASSED, pending approval (no implementation started)

## Clarity Breakdown
| Dimension | Score | Weight | Weighted |
|-----------|-------|--------|----------|
| Goal Clarity | 0.90 | 0.35 | 0.315 |
| Constraint Clarity | 0.80 | 0.25 | 0.200 |
| Success Criteria | 0.78 | 0.25 | 0.195 |
| Context Clarity | 0.78 | 0.15 | 0.117 |
| **Total Clarity** | | | **0.827** |
| **Ambiguity** | | | **0.173** |

## Topology
| Component | Status | Description | Coverage |
|-----------|--------|-------------|----------|
| Subtitle overlay window | active | Always-on-top transparent window, two modes | AC 1-4 |
| Recognition core (shared library) | active | Split Audio/Engines/Protocols out of the CLI so CLI and app share them | AC 5-6 |
| Controls | active | Menu-bar icon: start/stop, language (en-US, en-AU, ko-KR), settings, quit | AC 7-8 |
| Script recording | active | Timestamped text file of finalized sentences + on-screen scrollback | AC 9-10 |
| App packaging | active | Menu-bar app bundle, permissions, hardened runtime, Developer ID signing + notarization | AC 11-12 |

## Goal
A macOS menu-bar app that shows live subtitles of what it hears, built on the existing mac-stt engines. Primary use: in-person (offline) meetings with foreign speakers, where the user reads English speech on screen without touching the laptop and ends with a timestamped script. Secondary use: video calls (system audio). Speed is the top priority.

## Constraints
- Reuse the existing Swift engines (modern SpeechAnalyzer, legacy SFSpeechRecognizer fallback); no new third-party dependencies for recognition.
- Fully on-device recognition; no cloud models.
- Supported languages in the app: English (en-US), English-Australia (en-AU), Korean (ko-KR).
- Default engine settings favor speed: `--fast` equivalent, first word target about 2 seconds or less.
- Controls only via menu-bar icon (no global hotkey, no in-window buttons in this scope).
- Overlay has exactly two modes: bottom subtitle bar (1-2 large lines) and an expandable panel with scrollback.
- Distribution: formal (Developer ID signed + notarized). The user has a developer account.
- Existing CLI (`mac-stt`) must keep working unchanged.
- Target meeting: mid-size in-person meeting (2-4 m, 3-6 people), laptop on the table. Version 1 uses the built-in microphone only; accuracy for distant speakers is an accepted, unmeasured limitation.
- Version 1 must not preclude a later input-device picker (external USB/conference mic): the capture layer should take an optional device identifier.

## Non-Goals
- Input-device selection / external microphone support in version 1 (planned for a later version).
- Speaker identification / diarization (not provided by the Apple Speech SDK).
- Translation (e.g. English to Korean display).
- Global hotkey and in-overlay control buttons.
- LLM text polishing in the app (the CLI's `--polish` stays CLI-only unless re-scoped).
- Mac App Store distribution.

## Acceptance Criteria
- [ ] 1. The bottom subtitle bar shows the latest 1-2 lines in a large font, stays above other windows, and does not steal focus.
- [ ] 2. The user can switch between the bottom bar and the scrollback panel without stopping recognition.
- [ ] 3. The panel supports scrolling back through earlier finalized sentences and copying text.
- [ ] 4. The overlay position and size can be adjusted and are remembered across launches.
- [ ] 5. Audio, Engines and Protocols code lives in a shared library target used by both the CLI and the app; `swift test` passes for the library and the CLI builds with `make build`.
- [ ] 6. The app uses microphone input by default and can also use system audio.
- [ ] 7. The menu-bar icon offers Start/Stop, language choice (en-US, en-AU, ko-KR), source choice (mic/system), and Quit.
- [ ] 8. Changing language while running restarts recognition in the new language and shows the active language in the menu.
- [ ] 9. Every finalized sentence is appended to a timestamped (`[HH:mm:ss]`) text file as it is finalized, so a crash loses at most the sentence in progress.
- [ ] 10. The script file location is user-visible/configurable and a new file is created per session.
- [ ] 11. First launch requests microphone (and, for system audio, screen/system-audio recording) permission with clear usage text; denial shows an actionable message instead of failing silently.
- [ ] 12. A release build is signed with Developer ID, hardened runtime, and passes notarization and Gatekeeper (`spctl --assess`) on a clean Mac.
- [ ] 13. Measured with the same `say`-based method used for the CLI, first partial text appears within about 2 seconds of speech start.
- [ ] 14. The microphone capture API accepts an optional device identifier (default: system default input) so an input picker can be added later without redesign.
- [ ] 15. Before release, a manual field test in a 3-6 person meeting room is run and its observed accuracy/missed-speech notes are recorded (no numeric accuracy target is set in version 1).

## Assumptions Exposed & Resolved
| Assumption | Challenge | Resolution |
|------------|-----------|------------|
| The main input is system audio (Zoom, videos) | Round 1: what is the most common situation? | Primary is in-person meetings via microphone; video calls are secondary |
| "Script" means just subtitles | Round 2: what must remain after the meeting? | Timestamped text file plus on-screen scrollback; no speaker labels or translation |
| One overlay style is enough | Round 3: window shape | Two modes: subtitle bar and scrollback panel |
| Accuracy and speed are equal priorities | Round 4: latency target | Speed first, about 2 seconds or less |
| The app is for the user's own Mac | Round 5: distribution | Formal distribution with notarization |
| Several control methods are needed | Round 6: control method | Menu-bar icon only |
| Built-in mic is enough for a meeting room | Round 7-8: distance 2-4 m, 3-6 people; external mic? | Version 1 built-in only; external mic and device picker later; limitation accepted |

## Technical Context
- Existing code: `/Users/stoni/Projects/stt` (Swift 6 SPM, single executable target `mac-stt`). Layers: `Audio/` (MicrophoneCapture, SystemAudioCapture, PCMConverter), `Engines/` (ModernSpeechEngine, OnDeviceSpeechEngine, TextPolisher), `Protocols/TranscriberEngine.swift` (TranscriptionEvent, AudioCapture, TranscriberEngine, EngineOptions), `Output/OutputFormatter.swift` (terminal rendering, repetition guard).
- Apple's modern Speech API (SpeechAnalyzer) is Swift-only; the app must be Swift/SwiftUI/AppKit.
- Overlay windows are an AppKit concern (NSPanel, floating level, ignores-mouse-events option); SwiftUI can host the content.
- Packaging a notarized app is easiest with an Xcode project (or generated project) rather than SPM alone.
- Measured on the dev Mac: first word about 1.5 s with fast mode, about 5 s without.

## Open Risks (not resolved by interview)
- Far-field, multi-speaker accuracy of the built-in mic in a meeting room is unmeasured; a repetition guard exists but quality may need `--voice-processing`-style preprocessing or an external mic.
- macOS Voice Isolation mic mode behavior for a notarized app bundle is unverified.
- The modern engine needs macOS 26; the minimum supported OS for the app (fallback engine works on macOS 14) is an assumption to confirm during planning.
- Voice-processing mode (multi-channel input) has only been tested in a silent room.

## Ontology (Key Entities)
| Entity | Type | Fields | Relationships |
|--------|------|--------|---------------|
| TranscriptionEvent | core domain | text, isFinal, locale, timestamp | produced by Engine, consumed by Overlay and ScriptRecorder |
| Engine | core domain | modern or legacy, options (fast, vad, vocabulary) | consumes AudioCapture, emits TranscriptionEvent |
| AudioCapture | supporting | mic or system, voice processing | feeds Engine |
| Overlay | core domain | mode (bar or panel), position, size | displays TranscriptionEvent |
| ScriptRecorder | core domain | file path, session, timestamps | persists final TranscriptionEvent |
| MenuBarController | supporting | start/stop, language, source | controls Engine and Overlay |
| Language | supporting | en-US, en-AU, ko-KR | selects Engine locale |

## Ontology Convergence
| Round | Entities | New | Stability |
|-------|----------|-----|-----------|
| 1 | 4 (Event, Engine, Capture, Overlay) | 4 | n/a |
| 2 | 5 (+ScriptRecorder) | 1 | 80% |
| 3 | 5 | 0 | 100% |
| 4-5 | 6 (+MenuBarController, Language folded in) | 1 | 83% |
| 6 | 7 | 1 | 86% |

## Interview Transcript (summary)
- Round 0: Confirmed 4 components; user added language choice (English, English-Australia, Korean).
- Round 1: Primary use is in-person meetings with foreigners plus video calls; goal is writing a script.
- Round 2: Script = timestamped text file plus scrollback; no speaker labels, no translation.
- Round 3: Two overlay modes (subtitle bar and panel).
- Round 4: Speed first, about 2 seconds or less.
- Round 5: Formal distribution (account available); speech recognition must be as fast as possible.
- Round 6: Menu-bar icon only for controls.
- Round 7: Mid-size meetings (2-4 m, 3-6 people).
- Round 8: Built-in mic for version 1, external mic and input-device picker later.
