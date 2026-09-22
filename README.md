# Fn Dictate

Local-first macOS dictation and meeting notes — a Wispr Flow–style **hold Fn → speak → release → paste** workflow, plus a personal Notetaker. Everything runs on-device.

## Speech recognition

Final transcripts default to **[NVIDIA Parakeet TDT 0.6B v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2)** via [FluidAudio](https://github.com/FluidInference/FluidAudio) (Core ML on the Apple Neural Engine). Apple `SpeechAnalyzer` still drives live partials while you hold Fn.

| Mode | Behavior |
|---|---|
| **Parakeet** (default) | Higher English accuracy (names, accents, technical terms). Short wait after release while the buffered audio is re-decoded. |
| **Apple** | System SpeechAnalyzer only — fastest path, previous behavior. |

Switch in **Library → Formatting** or the menu bar (**Speech engine**). Models download once from Hugging Face on first Parakeet use and are cached locally. Cleanup and meeting notes still use Apple Foundation Models / Apple Intelligence when available.

## Requirements

- Apple Silicon Mac
- macOS 26+
- Xcode 26+
- Microphone + Accessibility (Screen Recording for system audio in meetings)
- Network once (first Parakeet model download); after that, fully offline ASR

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

`xcodegen generate` resolves the **FluidAudio** Swift package (Parakeet). First Xcode build may take longer while SPM fetches FluidAudio and compiles Core ML helpers.

## Usage

| Action | Shortcut |
|---|---|
| Dictate (push-to-talk) | Hold **Fn** (or **Ctrl+Opt**) |
| Cancel dictation | **Esc** while holding |
| Start / stop meeting | **⌥M** (Option+M), or menu bar |

- Short Fn taps (&lt; ~0.45s) do **not** start dictation (so Fn+function keys still work).
- Cursor / code editors stay near-raw; Mail / Outlook / Slack get Polished cleanup; browsers and everything else default to Light. Cleanup never invents content, and very short dictations skip the model.
- When you start from a detected Zoom / Teams / Meet call, recording **auto-stops** when that call ends (toggle in the menu bar).
- Each note stores the call **source** (Zoom desktop, Teams desktop, Teams in Edge/Chrome, Meet, etc.) so you can tell where it was held.
- Meetings save locally under Application Support → `FnDictate/meetings.json`.

## First-run permissions

1. Allow **Microphone**
2. Enable **Accessibility** for Fn Dictate
3. For meeting system audio: enable **Screen Recording**

See [SETUP.md](SETUP.md) for Wispr / BetterTouchTool / system Dictation conflict steps and Parakeet download notes.

## Privacy

Audio is processed on-device. There is no account, no cloud STT by default, and no telemetry. Parakeet weights are fetched from Hugging Face only for the one-time model install.
