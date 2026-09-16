# Fn Dictate

Local-first macOS dictation and meeting notes — a Wispr Flow–style **hold Fn → speak → release → paste** workflow, plus a personal Notetaker. Everything runs on-device with Apple SpeechAnalyzer and Foundation Models.

## Requirements

- Apple Silicon Mac
- macOS 26+
- Xcode 26+
- Microphone + Accessibility (Input Monitoring recommended; Screen Recording for system audio in meetings)

## Build & run

```bash
cd ~/Projects/fn-dictate
xcodegen generate
open FnDictate.xcodeproj
```

In Xcode: select the **FnDictate** scheme → Run (⌘R).

Or from the CLI:

```bash
xcodegen generate
xcodebuild -scheme FnDictate -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/FnDictate.app
```

## Usage

| Action | Shortcut |
|---|---|
| Dictate (push-to-talk) | Hold **Fn** (or **Ctrl+Opt**) |
| Cancel dictation | **Esc** while holding |
| Start / stop meeting | Menu bar → Start/Stop meeting |

- Short Fn taps (&lt; ~0.45s) do **not** start dictation (so Fn+function keys still work).
- Cursor / code editors get light cleanup; Edge / browsers get fuller polish.
- Meetings save locally under Application Support → `FnDictate/meetings.json`.

## First-run permissions

1. Allow **Microphone**
2. Enable **Accessibility** for Fn Dictate
3. Enable **Input Monitoring** if the Fn key does nothing
4. For meeting system audio: enable **Screen Recording**

See [SETUP.md](SETUP.md) for Wispr / BetterTouchTool / system Dictation conflict steps.

## Privacy

Audio is processed on-device. There is no account, no cloud STT by default, and no telemetry.
