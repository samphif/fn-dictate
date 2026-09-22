# Fn Dictate setup & conflict checklist

Use this after the first successful build so Fn hold works in **Cursor** and **Microsoft Edge**.

## 1. Grant permissions (then quit & relaunch the app)

System Settings → Privacy & Security:

- [ ] **Microphone** → Fn Dictate on
- [ ] **Accessibility** → Fn Dictate on (required for Fn capture + paste)
- [ ] **Screen Recording** (Screen & System Audio Recording) → Fn Dictate on (only if you want meeting system audio)

### Why Xcode keeps asking again (Mac only)

Debug builds must be signed with a **stable Development Team**. Without that, Xcode signs **ad-hoc**, every rebuild gets a new code hash (CDHash), and macOS TCC treats it as a *new app* — so Accessibility / Screen Recording look “missing” again.

This project now sets `DEVELOPMENT_TEAM`. After pulling that change:

1. In Xcode: **Product → Clean Build Folder**, then Run once.
2. Confirm signing: target → Signing & Capabilities → Team is set (not “None”).
3. Grant Microphone / Accessibility / Screen Recording **one more time**.
4. **Fully quit** the app (⌘Q) and Run again — Screen Recording often only applies after relaunch.

iPhone / iPad Simulator doesn’t use the same macOS Screen Recording TCC path, which is why you don’t see this loop there.

If Settings opens but Fn Dictate isn’t listed yet, toggle Screen Recording from the app’s Allow button (or start a meeting with system audio on) so macOS registers the binary, then enable the checkbox.

macOS often applies TCC changes only after a full quit/relaunch of the app.

## 2. Remove competing Fn consumers

### Wispr Flow

- [ ] Quit Wispr Flow completely (menu bar icon → Quit)
- [ ] If you keep Wispr installed, rebind its push-to-talk away from bare **Fn**



### BetterTouchTool

- [ ] Open BTT → Keyboard / Gestures
- [ ] Remove or disable any trigger that uses **Fn** / **Globe** alone
- [ ] Keep BTT for other remaps if you want — just not bare Fn hold



### macOS Dictation

- [ ] System Settings → Keyboard → Dictation
- [ ] Turn Dictation **Off**, **or** change its shortcut so it is **not** the Fn / Globe key

Apple’s built-in dictation is slow to start and will fight Fn Dictate for the same key.

### Cursor built-in dictation

- [ ] Prefer Fn Dictate for system-wide paste into Cursor
- [ ] If Cursor still steals Fn, check Cursor settings for dictation / voice keybindings and clear Fn



## 3. Verify the happy path

1. Click into a text field in **Notes** → hold **Fn** → speak → release → text pastes.
2. Repeat in **Cursor** (chat / composer).
3. Repeat in **Edge** (address bar or a form field).
4. Press **⌥M** (Option+M) → speak for ~30s → **⌥M** again → Library opens on Meetings; confirm summary + transcript.
   (Menu bar Start/Stop still works if you prefer clicking.)



## 4. Troubleshooting


| Symptom                         | Likely fix                                                                      |
| ------------------------------- | ------------------------------------------------------------------------------- |
| Fn does nothing                 | Accessibility; quit & relaunch; re-toggle after Xcode rebuilds                  |
| Waveform/listening but no paste | Accessibility permission                                                        |
| macOS Dictation UI also appears | Disable system Dictation Fn shortcut                                            |
| External keyboard has no Fn     | Use **Ctrl+Opt** hold instead                                                   |
| Meeting missing remote audio    | Enable Screen Recording + “Include system audio”                                |
| Cleanup sounds unpolished       | Enable Apple Intelligence (Foundation Models); basic cleanup still runs offline |
| First dictate hangs / “Downloading Parakeet…” | Wait for the one-time Hugging Face model fetch (needs network); or set Speech engine → Apple |
| Parakeet paste falls back to weaker words | Confirm Speech engine is **Parakeet** in menu bar / Library → Formatting; wait for model ready |


## 5. Speech engine (Parakeet)

Fn Dictate defaults to **Parakeet TDT 0.6B v2** (FluidAudio) for the final transcript after you release Fn. Live partials still use Apple Speech.

- Menu bar → **Speech engine**, or Library → **Formatting** → Speech recognition
- First Parakeet use downloads Core ML models (~once); later runs are offline
- If download fails or you want maximum speed, switch to **Apple**


## 6. Data location

`~/Library/Application Support/FnDictate/`

- `history.json` — recent dictations
- `meetings.json` — meeting notes library

