# Changelog

## 1.0.2

**HUD**
- The recording pill stays visible on every Space and follows the active display
  instead of the main one.
- Close (×) and "copy to clipboard" buttons inside the recording pill, with tooltips.

**Menu bar**
- Optional "Show icon in menu bar" switch. With the icon hidden, launching the app
  again opens Settings, and a Quit button is available there.

**Recognition**
- Empty initial prompt by default: an English term list could bias the decoder and
  drop whole chunks of Russian speech. The field remains for those who need it.
- Timestamps are always enabled — without them WhisperKit can lose chunks of long
  audio and punctuates worse.
- Leading and trailing silence is trimmed before decoding, so hallucinated tails
  ("Спасибо.", "Продолжение следует…", "Gracias") no longer appear.
- A clip with no speech shows "Nothing recognized" instead of a hallucination.

**Debug builds**
- Every dictation is saved as a WAV next to the log, together with the raw and
  cleaned recognized text.

## 1.0.1

**Insertion**
- Character-by-character typing no longer dies after a long session and works in
  terminals: every chunk is now a proper keyDown/keyUp pair, sent in smaller
  pieces so the target app keeps up.
- Secure input (password fields, `sudo`, terminals with secure keyboard entry) is
  detected: the text goes to the clipboard and a notice explains why.
- Without Accessibility every typing mode falls back to the clipboard with a
  notice instead of silently doing nothing.

**Housekeeping**
- Unused Apple Events entitlement removed.

## 1.0.0 — first public release

Local voice dictation for macOS.

**Recognition**
- Whisper large-v3-turbo on the Apple Neural Engine (Core ML), model kept resident.
- Automatic language detection, fixed language (RU/EN and 12 more), initial prompt
  for mixed-language speech.
- Models are downloaded on demand, run locally, audio never leaves the Mac.

**Dictation**
- Global hotkey: a key combination or a double tap of a modifier (Fn, left/right
  Option, left/right Command).
- Bottom-of-screen capsule with a recording timer and level meter.
- Three insertion modes: character typing (default), ⌘V with clipboard restore,
  clipboard only.
- The overlay never takes focus and stays visible across Spaces and full-screen apps.

**Microphone**
- Input device selection with pinning (the built-in microphone keeps AirPods in A2DP).
- Automatic fallback to the system default when the selected device disappears.
- Device changes during recording are handled without losing captured audio.

**Models**
- Model manager: real sizes from Hugging Face, circular progress, cancel, delete,
  custom folders, and a model test using a synthesized phrase.
- SHA-256 verification of every downloaded weight file.

**Other**
- RU/EN interface with instant switching.
- Launch at login (login item).
- Single-instance guard.
- Update checks through GitHub Releases.
- Developer ID signing and Apple notarization.
