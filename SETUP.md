# Fn Dictate setup & conflict checklist

Use this after the first successful build so Fn hold works in **Cursor** and **Microsoft Edge**.

## 1. Grant permissions (then quit & relaunch the app)

System Settings → Privacy & Security:

- [ ] **Microphone** → Fn Dictate on
- [ ] **Accessibility** → Fn Dictate on
- [ ] **Input Monitoring** → Fn Dictate on (needed for reliable Fn capture)
- [ ] **Screen Recording** → Fn Dictate on (only if you want meeting system audio)

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
4. Menu bar → **Start meeting** → speak for ~30s → **Stop meeting** → open Meeting notes and confirm summary + transcript.

## 4. Troubleshooting

| Symptom | Likely fix |
|---|---|
| Fn does nothing | Input Monitoring + Accessibility; relaunch app |
| Waveform/listening but no paste | Accessibility permission |
| macOS Dictation UI also appears | Disable system Dictation Fn shortcut |
| External keyboard has no Fn | Use **Ctrl+Opt** hold instead |
| Meeting missing remote audio | Enable Screen Recording + “Include system audio” |
| Cleanup sounds unpolished | Enable Apple Intelligence (Foundation Models); basic cleanup still runs offline |

## 5. Data location

`~/Library/Application Support/FnDictate/`

- `history.json` — recent dictations
- `meetings.json` — meeting notes library
