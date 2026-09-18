# Fn Dictate

Local-first macOS dictation and meeting notes — a Wispr Flow–style **hold Fn → speak → release → paste** workflow, plus a personal Notetaker. Everything runs on-device with Apple SpeechAnalyzer and Foundation Models.

## Requirements

- Apple Silicon Mac
- macOS 26+
- Xcode 26+
- Microphone + Accessibility (Screen Recording for system audio in meetings)

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
| Start / stop meeting | **⌥M** (Option+M), or menu bar |

- Short Fn taps (&lt; ~0.45s) do **not** start dictation (so Fn+function keys still work).
- Cursor / code editors stay near-raw; Mail / Outlook / Slack get Polished cleanup; browsers and everything else default to Light. Cleanup never invents content, and very short dictations skip the model.
- When you start from a detected Zoom / Teams / Meet call, recording **auto-stops** when that call ends (toggle in the menu bar).
- Meetings save locally under Application Support → `FnDictate/meetings.json`.

## First-run permissions

1. Allow **Microphone**
2. Enable **Accessibility** for Fn Dictate
3. For meeting system audio: enable **Screen Recording**

See [SETUP.md](SETUP.md) for Wispr / BetterTouchTool / system Dictation conflict steps.

## Privacy

Audio is processed on-device. There is no account, no cloud STT by default, and no telemetry.
