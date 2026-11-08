# Ieum

Live captions and translation for meetings, on a Mac, entirely offline.

Built for a Korean speaker in a meeting with native English speakers: the other side talks, you read Korean;
you answer in Korean, and the English is there for them. Speech recognition and translation run on the Mac
(Apple's Speech and Translation frameworks). There is no account, no cloud and no network use.

## Features

- **Meeting modes**: English → Korean, Korean → English, **Conversation** (both ways, language detected per sentence), or captions only.
- **Subtitle bar** for reading at a glance, **transcript panel** for scrolling back. Bar lines, text size, background style and opacity are adjustable; the overlay fades when nobody speaks and can be click-through.
- **Meeting vocabulary**: names and jargon you list are corrected in the transcript before it is translated.
- **Transcripts** are saved per meeting (`[HH:mm:ss] text` with `→ translation` lines; `[EN]`/`[KO]` tags in conversation mode) and listed in Settings.
- Korean and English interface, first-run permission check, global shortcuts (⌃⌥S start/stop, ⌃⌥H show/hide, ⌃⌥D bar/panel), open at login.
- `ieum-cli`: a command-line version of the recognizer (text or JSON Lines).

Requires macOS 14 or later; the fast recognizer, conversation mode and translation need macOS 26.4 or later.

## Build

```sh
make build          # CLI
make app            # Ieum.app (ad-hoc signed, runs on this Mac)
make test
make app-release SIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=<notarytool profile>   # signed + notarized
make dmg SIGN_IDENTITY=… NOTARY_PROFILE=…
```

## Benchmarks

`make bench LABEL=<name> [BASELINE=<earlier label>]` plays synthesized speech through the real engines in real time and writes
`Benchmarks/results/<name>.md`. See [docs/BENCHMARKS.md](docs/BENCHMARKS.md) for what changed between versions and
what the numbers do not tell you.

## Layout

| Path | What |
|---|---|
| `Sources/IeumCore` | audio capture, recognizers, conversation arbitration, translation pipeline, transcript recorder |
| `Sources/Ieum` | the menu-bar app (overlay, settings, setup) |
| `Sources/IeumCLI` | command-line tool |
| `Sources/IeumBench` | benchmark tool |
| `docs/UX-REVIEW.md` | UX findings and decisions |
