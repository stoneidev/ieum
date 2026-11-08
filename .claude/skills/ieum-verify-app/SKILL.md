---
name: ieum-verify-app
description: Build, launch and verify the Ieum menu-bar app on this Mac: capture only its windows, press its buttons, feed it speech with say, read the saved transcript. Use after any UI, timing or recognition change.
---

# Verify Ieum in the running app

Why not just run tests: layout, permissions, audio timing and the two recognizers only show up in the real app.

## 1. Build and launch

```sh
export SIGN_IDENTITY="Developer ID Application: <name> (<team id>)"
Scripts/dev-run.sh -meetingMode englishToKorean -source microphone -displayMode panel
```
`dev-run.sh` runs `make app`, re-signs with the Developer ID identity (so the microphone, speech and screen grants stay valid; an ad-hoc build asks again and
`Starting…` hangs behind a permission dialog) and opens a fresh instance with launch arguments that override saved settings for this run.
Keep the display awake: `caffeinate -u -t 900 &`.

## 2. Find and capture a window (never the full screen)

```sh
swiftc -O Scripts/window-info.swift -o /tmp/window-info
/tmp/window-info            # id, title, bounds of each Ieum window: "Captions" (overlay), "Ieum 설정", "권한 점검"
screencapture -x -o -l <id> /tmp/shot.png
```
The overlay may sit on a second display; `-l` captures it anyway. A full-screen capture shows the owner's other windows: do not take one.

## 3. Drive it with accessibility (System Events)

```sh
osascript -e 'tell application "System Events" to tell process "Ieum" to click button 1 of group 1 of window "Captions"'   # Start / Stop
osascript -e 'tell application "System Events" to tell process "Ieum" to click radio button 2 of tab group 1 of group 1 of window "Ieum 설정"'   # settings tab 1..5
open -n .build/app/Ieum.app            # while running (no -n) it opens the settings window
```
The status-bar menu is not reachable this way. Global hot keys cannot be triggered with synthetic key events.

## 4. Feed it speech

```sh
say -v Samantha -r 190 "Could you share the schedule for next week? [[slnc 900]] We need to confirm it by tomorrow."
say -v Yuna "다음 주 일정을 공유해 주시겠어요?"
```
Use the microphone source; the speakers are heard by the mic. `[[slnc 900]]` inserts a 0.9 s pause, which is the case that exposed the pause-finalization bug.
For frame sequences, loop `screencapture -l` every 0.1–0.4 s and stack the frames with a small AppKit script.

## 5. What to check

- Words appear one by one (early words), the translation follows about a second later; the spoken language is above its translation.
- Every sentence starts with its first word after pauses (no `,..`, `be... I am`).
- After Stop the panel keeps its translations and shows the Start button; a new transcript file exists in `~/Documents/Ieum Transcripts`.
- Settings tabs render without cut-off text. Setup window shows microphone, optional screen audio, optional speech recognition, translation.
- Check the saved script (`cat` the newest file in `~/Documents/Ieum Transcripts`) when a screenshot is ambiguous.

Quit the app when done (`pkill -x Ieum`), restore any setting you changed with `defaults write today.calmwork.ieum …`, and say in the report that the room sound
may have been transcribed during the test.
