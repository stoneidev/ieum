# AGENTS.md

Guide for any coding agent (or person) who continues work on **Ieum** (이음) on another machine or in a new session.
Read this first, then `docs/PRD.md` (what the product is and why it is built this way) and `docs/BENCHMARKS.md` (measured evidence).

## What this is

Ieum is a macOS menu-bar app that shows live captions and English ↔ Korean translation during meetings. Recognition and translation run
on the Mac (Apple Speech and Translation frameworks); there is no cloud and no account. Swift 6, Swift Package Manager, no Xcode project.

- Product name **Ieum** (이음, "to connect"). Internal modules are named by function, not by product (`CaptionCore`, `OverlayApp`, …).
- Repo: https://github.com/stoneidev/ieum (public, Apache-2.0, copyright holder in `NOTICE`). Homebrew tap: https://github.com/stoneidev/homebrew-tap (`brew install --cask stoneidev/tap/ieum`; cask in `Casks/ieum.rb`, kept outside this repo, usually at `~/Projects/homebrew-tap`). Site: https://ieum.calmwork.today (Cloudflare Pages project `ieum`).
- Bundle id `today.calmwork.ieum`. Distribution: Developer ID signed + notarized DMG attached to GitHub Releases.

## Working with the owner

- The owner writes Korean. Answer in Korean **all the way through, including the short progress lines between tool calls** (in a long session those drifted into Japanese once); keep code, commit messages, README and release notes in English (`docs/PRD.md`, `docs/UX-REVIEW.md`
  and `docs/USER-GUIDE.md` are Korean on purpose).
- Report honestly: say what was verified (and how) and what was not. Unverified items are listed in `docs/PRD.md` §9.
- Ask before outward-facing or hard-to-undo actions (publishing, notarizing, deleting, changing repo visibility). The owner has authorized releases
  case by case: "배포 / 푸시 / tag / 바이너리" in one message means the whole release runbook in `.claude/skills/ieum-release`.
- Commit trailer: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` (use the model that actually wrote the change).
- Never move or re-create an existing tag. Never capture the full screen (see "Verifying the app").
- Do not put personal data (legal name, Apple team id) into the repo. Pass the signing identity through `SIGN_IDENTITY`.

## Repository map

| Path | What |
|---|---|
| `Sources/CaptionCore` | Library shared by everything: audio capture, speech engines, conversation arbitration, translation pipeline, transcript recorder, text cleaning |
| `Sources/OverlayApp` | The menu-bar app (product `Ieum`): `AppModel` (state, sessions), overlay window and views, settings, setup, menu, hot keys |
| `Sources/CaptionCLI` | `caption-cli`, a command-line recognizer |
| `Sources/CaptionBench` | `caption-bench`, the benchmark runner |
| `Tests/CaptionCoreTests` | Swift Testing suites for the library (314 tests) |
| `Resources` | Info.plists (app + CLI), `entitlements.plist`, app icon |
| `Benchmarks` | Audio generation (`say`), reference texts, `run.sh`, `report.py`, results per version |
| `Scripts` | `dev-run.sh`, `deploy-site.sh`, `window-info.swift`, `make-icon.swift` |
| `site-src` | The website template: every sentence in English, Korean, Japanese and Chinese as adjacent `<span class="en|ko|ja|zh">`. `Scripts/build-site.py` writes one page per language (`/`, `/ko/`, `/ja/`, `/zh/`) with its own head (hreflang, JSON-LD), plus `sitemap.xml` and `llms-full.txt` |
| `site` | Static site files that are copied as they are (fonts, icons, `og.png`, `robots.txt`, `llms.txt`, `_headers`); deployed with `Scripts/deploy-site.sh` (`--preview` for a preview URL) |
| `docs` | `PRD.md`, `USER-GUIDE.md`, `BENCHMARKS.md`, `UX-REVIEW.md` |
| `.claude/skills` | Runbooks: `ieum-release`, `ieum-verify-app`, `ieum-benchmark` (plain Markdown, usable by any agent). Other skills the owner installed locally (for example `ui-ux-pro-max`, used for the UI/site design work) are not committed |
| `.omc` | Planning artifacts from earlier sessions (`prd.json`, interview spec). History only; `docs/PRD.md` is the current statement |

Key types: `VocabularySuggester` + `AppModel+Vocabulary` + `VocabularyViews` (nudges to fill the vocabulary: tip while empty, card after a meeting with names heard, one tap each; suggestions are found on the Mac only), `ReplyHelper` + `ReplyModel` + `ReplyPanelController` (the reply helper, ⌃⌥R: the translation run from the language you read to the one you hear, optionally smoothed by Foundation Models behind `ReplyHelper.acceptsPolished`; history in memory only), `SupportState` + `AppModel+Support` (the one friendly coffee ask: counted on the Mac only, asked after a finished meeting at the 3rd/12th/30th real meeting, answers: buy / not now / never; a restart is not a meeting; no network request except the user's click that opens the page; Buy Me a Coffee URL in `Support.coffeeURL`), `Scenario` (conversation / meeting / seminar: which sources and the both-sides mode are offered, defaults when chosen, and the notes `MinutesTemplate`; `AppModel.setScenario` applies them), `MeetingSetup` (the language the other side speaks, the language you read or none, and whether both sides speak; any two of `SpokenLanguage` en/ko/ja/zh work together; it replaced the five `MeetingMode`s and the language pairs), `InputDevices` (microphone list and the fallback when a saved device is unplugged), `BarControls` (text size, bar/panel, ⋯ menu on the subtitle bar), `AppModel` (the @MainActor state machine: start/stop, session task, translation wiring, bar/panel state), `MeetingSetup` (language rules), `EngineFactory` (picks the engine), `ModernSpeechEngine` (SpeechAnalyzer), `OnDeviceSpeechEngine` (SFSpeechRecognizer),
`PreviewingEngine` (both together: early words), `ConversationEngine` + `LanguageArbiter` (auto-detect mode), `TranslationPipeline`
(single-flight, ordered finals, latest-wins interims), `VocabularyCorrector`, `TranscriptCleaner`, `ScriptRecorder`, `MeetingMinutes` + `MinutesSource` + `MinutesMarkdown` (pure minutes logic: parts, validated line citations, Markdown) with `MinutesGenerator` in OverlayApp (Foundation Models, macOS 26); `AppModel+Minutes` owns the panel's minutes state (a `minutesRun` counter makes late results of a cancelled run harmless).

## Commands

```sh
make build                    # caption-cli (release, ad-hoc signed)
make app                      # .build/app/Ieum.app (ad-hoc signed; runs on this Mac)
make test                     # or: swift test   (314 tests; must stay green)
Scripts/dev-run.sh [launch args]   # build, re-sign with $SIGN_IDENTITY, relaunch the app
make bench LABEL=x BASELINE=y # benchmark suite -> Benchmarks/results/x.md
Scripts/deploy-site.sh        # site -> Cloudflare Pages
```

After every release also update the Homebrew cask (`version` and `sha256` of the public DMG, `brew audit --cask --online stoneidev/tap/ieum`, push); it is step 10 of the runbook. The tap must be trusted on a Mac once (`brew trust stoneidev/tap`).
Release (signed + notarized, needs the owner's Developer ID and a `notarytool` keychain profile): see `.claude/skills/ieum-release/SKILL.md`.
Build must stay warning-free; `make build` and `make app` print none today.

Launch arguments override saved settings for one run: `-heardLanguage en|ko|ja|zh`, `-shownLanguage en|ko|ja|zh` (leave it out for captions only), `-bothWays YES|NO`,
`-source microphone|system|call`, `-displayMode bar|panel`, `-scenario conversation|meeting|seminar`, `-hidesFromSharing YES|NO`, `-pointerAvoidance fade|dodge|off`.

## Verifying the app

**The overlay is hidden from screen capture by default** (`sharingType = .none`), so `screencapture -l <id>` fails with "could not create image from window". Launch the app for verification with `-hidesFromSharing NO`. The check that it really is hidden from ScreenCaptureKit is `Scripts/check-share-safe.swift`. Pointer avoidance (fade/dodge) is easiest to verify by moving the cursor with `CGWarpMouseCursorPosition` and reading `kCGWindowAlpha` / the window bounds from `CGWindowListCopyWindowInfo`, since a window capture does not show the window's alpha.

Read `.claude/skills/ieum-verify-app/SKILL.md`. In short: re-sign the build with Developer ID so the microphone/speech grants survive,
find the window id with `Scripts/window-info.swift`, capture **only that window** (`screencapture -x -o -l <id>`), drive buttons with
AppleScript accessibility (`click button 1 of group 1 of window "Captions"`), play speech with `say -v Samantha`, and keep the display awake
(`caffeinate -u -t 900`). Tests alone are not enough for UI or timing changes.

## Rules that came from mistakes

- **Changing the notes prompt (`MinutesPrompt`, `MinutesWriter`, `MeetingMinutes.validated/grounded`) means running `minutes-eval`** (docs/BENCHMARKS.md, "Meeting-notes prompt") before and after and recording the numbers. Lessons from it: an example in the instructions is copied into other meetings (keep it unrelated and say so); a phrase named in a "do not" rule is copied too; the model invents list items that cite no line; the default guardrails refuse ordinary talks, so the session uses `.permissiveContentTransformations`.
- **The reply helper must never present a rewrite that changes the meaning.** The smoothing step is accepted only through `ReplyHelper.acceptsPolished` (question stays a question, numbers and capitalised names kept, not much shorter). It was written after a real run turned a question into a statement and dropped a clause; keep the literal translation visible and add a test when a new failure shows up. Dictation (mic button) is unverified on the dev Mac (lid closed).
- **Screen-share safe is a promise with a verified scope.** `sharingType = .none` was checked with ScreenCaptureKit on macOS 26.6 only (display capture, one pixel read). Do not word it as absolute ("never"), keep the scope in the README, site and settings text, and re-run `Scripts/check-share-safe.swift` when macOS changes. Sharing a single window is not covered.
- **Pause finalization.** Asking the recognizer to finalize at a pause (`pauseFinalization`) damages the first words of the next English sentence
  (word error rate 7 % → 15–20 %), so English single-language modes switch it off. Korean and the auto-detect mode need it. Evidence in `docs/BENCHMARKS.md`.
  Do not re-enable it for English without re-running the gap benchmark.
- **Never finalize an already-finalized region**: it ends the SpeechAnalyzer session (`RecogRejected`). `SessionFlags` guards this.
- **`@Published` sinks see the old value.** Use the emitted value, and defer window resizing with `.receive(on: DispatchQueue.main)`.
- **Re-signing changes the TCC identity.** Ad-hoc builds lose microphone/speech/screen grants; sign local builds with the Developer ID identity.
- **`contextualStrings` do nothing for SpeechTranscriber** (measured). The meeting vocabulary is applied afterwards by `VocabularyCorrector`.
- **macOS has a case-insensitive file system**: the CLI is `caption-cli` so it cannot collide with the app executable `Ieum`.
- **Notarization uploads can hang** (no network connection, no submission in `notarytool history`). Kill `notarytool submit` and rerun only `make dmg`.
- **Do not publish `site/.omc`** (hook state): deploy through `Scripts/deploy-site.sh`. Edit the site in `site-src/index.template.html` (all four languages in the same place); `python3 Scripts/build-site.py /tmp/out --allow-missing` builds it for a local look, and the real build fails on any sentence without a translation.
- **Status items are hosted by Control Center on macOS 26** (window owner "제어 센터"/Control Center, layer 25, named by `autosaveName`) and the left-most ones are hidden when the bar is full. The status item has its own `autosaveName` (unnamed items share "Item-0" visibility with other apps), and the overlay carries a ⋯ menu with the same actions so the app is never out of reach.
- **Display sleep breaks ScreenCaptureKit and screenshots.** Use `caffeinate -u`.
- **zsh does not word-split unquoted variables**; use arrays. BSD `sed` has no `-i` without a suffix; use Python or `perl -pi`.
- **Early words do not work for Japanese and Chinese on this Mac**: the legacy recognizer has no on-device ja-JP / zh-CN model, so `PreviewingEngine` quietly runs without the preview there (docs/TRANSCRIPTION-RESEARCH.md). The pause rule stays on for ja/zh like Korean (it costs no accuracy there).
- **Minutes draft (Foundation Models)**: the model must be given a small part (`MinutesSource.chunks`) and bounded output (`.maximumCount(6)` on the lists); repetitive input without the cap made one part take minutes. Output is always a draft: every point cites transcript line numbers and invalid ones are dropped in `MeetingMinutes.validated`. Do not present it as a record, and do not call it from a path that is not behind `#available(macOS 26.0, *)` and `unavailableReason`.
- Experiments that did not pay off are written down (`docs/BENCHMARKS.md`, "Tried and not kept"). Add yours there, with numbers.

## Updates (the app updates itself)

`Updater.swift` reads the feed `https://ieum.calmwork.today/latest.json` (written by `Scripts/deploy-site.sh` from the latest GitHub release: version, DMG url,
SHA-256, size, notes), asks, downloads, verifies (SHA-256, same Team ID, `codesign`, `spctl`, bundle version) and swaps the app with a small shell script after quit.
Pure decisions (`UpdateCheck`, `UpdateFeed`) live in CaptionCore and are tested. Rules:
- **Ship order matters**: create the GitHub release first, then run `Scripts/deploy-site.sh`; publishing the feed is what offers the release to installed apps.
- Release notes: English bullets, a line `---`, then Korean bullets (both become the update window's notes). **Keep them to 3 one-line bullets** (about 52 English / 26 Korean characters each): the update window of every app up to 0.13.0 has a fixed height, and 0.13.0's long notes pushed its title and its "Update now" button out of the window. Installed apps cannot be fixed afterwards, so `Scripts/deploy-site.sh` refuses notes that take more than 4 lines. From the version after 0.13.0 the notes scroll inside the window, but old clients keep the old layout for as long as they exist. If a release's notes were too long, `gh release edit vX.Y.Z --notes …` and run `Scripts/deploy-site.sh` again: the feed is rebuilt from the release.
- The privacy statement is "the only request is the optional update check". Do not add other requests, and keep the toggle. The coffee ask is local counting plus a page that opens only on the user's click; keep it that way (never ping a server to count supporters).
- Test without publishing anything: serve a folder with `python3 -m http.server 8765` containing `latest.json` (+ a DMG whose app version equals the feed version) and run
  a **copy** of the app: `open -n /tmp/X/Ieum.app --args -updateFeedURL http://localhost:8765/latest.json -updateCurrentVersion 0.0.1`. Reset `defaults delete today.calmwork.ieum lastUpdateCheck`
  between runs (checks are once a day). The copy is replaced by the DMG's app and relaunched. A feed with a wrong sha256 must be refused.

## Release highlights ("What's new")

`WhatsNewCatalog.pages()` in `Sources/OverlayApp/WhatsNewView.swift` lists the user-visible highlights, newest first, each with the version that introduced it.
When a release adds something people should notice, add a page (title and body in both languages, and an `Art` scene or reuse one) before building the release.
The window opens once after an update and shows only pages newer than `Preferences.lastSeenVersion`; selection logic is `WhatsNew.pending` (tested). Try it with
`open -n .build/app/Ieum.app --args -lastSeenVersion 0.2.3`. Synthetic mouse/Esc input does not reach it from the agent shell (the app is not activated there), so judge the
look from window screenshots.

## Type in the app's own windows

The What's new tour and the update window use **Ieum Sans** (`Typeface.font(size, weight)`): Pretendard 1.3.9 subset to KS X 1001 Hangul + Latin + the symbols used, renamed
(the OFL reserves the name Pretendard), three weights in `Resources/App/Fonts`, copied into the bundle by `make app-bundle` and registered with `ATSApplicationFontsPath`.
If a string needs a Hangul syllable outside the subset, macOS falls back to the system font for that glyph. To regenerate: download the Pretendard release, run `pyftsubset` with
the syllable list, rename the name table (families "Ieum Sans", PostScript `IeumSans-<Weight>`). SwiftUI note: a text chip with `.opacity` inside an `.overlay` rendered upside
down once; `.compositingGroup()` before `.opacity` fixed it.

## Conventions

- Match the surrounding code: comments explain *why*, not what; no dead code; small diffs.
- UI strings go through `tr("English", "한국어")`; every user-visible string needs both.
- Add or update tests for logic in `CaptionCore` (Swift Testing, `#expect`; mutating calls cannot sit inside `#expect`, bind them first).
- UI and latency changes are measured: use the bench flags (`--early-words`, `--no-fast`, `--no-vad`, `--pause`, `--no-pause-finalization`)
  and record results.
- Settings live in `UserDefaults` under the bundle id (`today.calmwork.ieum`); `Preferences.swift` is the only place that reads or writes them.
- Transcripts are saved to `~/Documents/Ieum Transcripts` (text only; audio is never written).

## State at hand-off

- Latest published release is **v0.14.2** (build 28), tagged, on GitHub Releases, in the Homebrew tap and on the site (`latest.json` says 0.14.2). `main` is clean and pushed. History: v0.1.0 CLI baseline → v0.2.0 conversation/vocabulary/benchmarks → rename to Ieum → v0.2.x polish → v0.3.0 in-app updates + bar/panel toggle + Ieum Sans popups → v0.3.1 microphone picker → v0.3.2 bar controls (text size buttons, ⋯ menu also while captions run) → v0.4.0 Japanese and Chinese, with the language choice reduced to "language you hear" / "language you read" and a both-sides switch (`MeetingSetup`) → v0.4.1 downloadable translation languages → v0.5.0 spoken-time stamps, SRT/VTT/Markdown export, naming → v0.6.0 call mode (Me/Them) → v0.7.0 minutes draft with cited lines (Foundation Models) → v0.7.1 the minutes item is shown only on Macs with Apple Intelligence → v0.8.0 meeting view: language labels on spoken/translated lines, Conversation | Minutes tabs in the panel, wrap-up prompt, minutes in the ⋯ and menu-bar menus → v0.9.0 situations (conversation / meeting / seminar) and normalized notes → v0.10.0 the coffee ask → v0.11.0 the situation is chosen on the panel and the idle bar (`SituationChip`, `SituationPicker`), not only in Settings → v0.12.0 screen-share safe + pointer avoidance → v0.13.0 the reply helper (⌃⌥R) → v0.14.0 translate-or-captions-only is one choice next to the situation (`LanguageRouteChip`, `MeetingSetup.translating`) → v0.14.1 nudges to fill the vocabulary → v0.14.2 the reply and bar/panel buttons no longer look alike.
- Tests: 314 (`swift test`). Build is warning-free.
- Site download counter is the sum of GitHub `download_count` over all releases, shown from 25 up. It includes the maintainer's own verification downloads and auto-updates, so it is not a user count.
- Open items and ideas are in `docs/PRD.md` §10–11. The most useful next steps: other language pairs (biggest reach), early words in auto-detect mode, keeping the pause-finalization speed without the damage,
  testing the low-latency translation model (not installed on the dev Mac), a real meeting-room test (including an external microphone: only the device switch was verified, not recognition from it), an English user guide.
- Unverified: real-internet update from an older version, replacing an app in /Applications, first launch on another Mac, `brew install` on a clean Mac, the site on mobile widths.
- Domain `ieum.calmwork.today` is connected to the Pages project.
