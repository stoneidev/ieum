# Package layout

Ieum is one Swift package (`Package.swift`) with a shared library and thin executables. That matches a mid-size macOS app: real module boundaries where they already pay off (`CaptionCore` vs UI/CLI tools), without a package-per-feature graph.

## Targets (do not proliferate casually)

| Target | Role |
|---|---|
| `CaptionCore` | Pure and Mac-framework logic shared by the app and tools: capture, engines, translation pipeline, transcripts, minutes validation, update feed decisions |
| `OverlayApp` | Menu-bar product (`Ieum`): AppKit/SwiftUI shell, preferences, overlay |
| `CaptionCLI` / `CaptionBench` / `MinutesEval` | Command-line tools that depend on `CaptionCore` |
| `CaptionCoreTests` | Unit tests for `CaptionCore` (Swift Testing) |

Keep product behavior in `CaptionCore` when it can be tested without a GUI session. Keep windowing, menus, and SwiftUI in `OverlayApp`. Prefer **folders inside a target** over new SPM targets unless you need a hard dependency or link boundary.

## Folders inside a target

Organize by **domain** (what the code is about), not by file type. Existing layer folders in `CaptionCore` (`Audio`, `Engines`, `Translation`, `Output`, `Protocols`) stay; newer product areas use the same idea:

```
Sources/CaptionCore/
  Audio/ Engines/ Translation/ Output/ Protocols/
  Meeting/   Scenario, MeetingSetup, MeetingApps
  Reply/     ReplyHelper, ReplyHistory, ReplyPrompt
  Text/      TranscriptCleaner, vocabulary, TextMetrics
  Support/   coffee-ask state
  Updates/   update feed / What's new selection
  Display/   pointer avoidance (pure geometry + fade policy)

Sources/OverlayApp/
  App/         entry, AppModel, Preferences, Models, L10n
  Overlay/     subtitle bar, panel chrome, screen-share helper
  Reply/ Minutes/ Settings/ Menu/ Updates/ Support/ Vocabulary/
  Transcripts/ Windows/

Tests/CaptionCoreTests/
  <same domain names as CaptionCore>/
```

SPM compiles every `.swift` file under a target `path`; subfolders are for humans and for mirroring tests. Moving a file between folders **inside the same target** does not change the public API.

## Where to put a new file

1. Shared, testable logic → `Sources/CaptionCore/<Domain>/` and a test under `Tests/CaptionCoreTests/<Domain>/`.
2. App-only UI or AppKit wiring → `Sources/OverlayApp/<Feature>/`. Prefer colocating `AppModel+Feature.swift` with that feature's views.
3. Need a new SPM target only if another executable must link a subset, or a dependency cycle appears. Otherwise a folder is enough.

## Large types

Prefer one type (or a small cluster) per file once a file grows past a screenful of unrelated views. Same-module splits are cheap; cross-module extractions need a clear public surface and tests.

## CI

`.github/workflows/ci.yml` runs on `macos-26` and builds/runs **`CaptionCoreTests` only** (plus a release build of `CaptionCore`). It does not compile `OverlayApp` on the runner: Xcode 26.6’s Swift frontend has crashed there with `SmallVector unable to grow` while IR-generating `SettingsView.swift`. Treat a green CI as coverage of shared library logic; verify the menu-bar app with `make app` / the verify-app skill on a Mac.
