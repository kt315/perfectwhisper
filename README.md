# PerfectWhisper

Local voice dictation for macOS. Lives in the menu bar, records the microphone on a
global hotkey, transcribes with Whisper on the Apple Neural Engine and inserts the
text into the active app — or just puts it on the clipboard.

No account, no cloud, no telemetry. Audio never leaves your Mac.

## Features

- **Whisper large-v3-turbo** running locally via Core ML on the Neural Engine.
- **Global hotkey**: a key combination or a double tap of Fn, Option or Command.
- **Three insertion modes**: character-by-character typing (default), paste with
  clipboard restore, or clipboard only.
- **Microphone selection** with device pinning, so Bluetooth headphones stay in
  A2DP and music quality does not drop.
- **Model manager**: download with progress and cancel, delete, custom folders,
  and SHA-256 verification of every downloaded weight file.
- **Floating HUD** with a recording timer and level meter that never steals focus.
- **RU/EN interface** with instant switching.
- **Launch at login**, single-instance guard, no telemetry.
- **Update checks** through GitHub Releases (optional GitLab support).

## Requirements

- macOS 27 or later, Apple Silicon
- Xcode 27 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) only if you need to regenerate
  the project: `brew install xcodegen`

## Install

Download `PerfectWhisper-1.0.2.dmg` from the
[releases page](https://github.com/kt315/perfectwhisper/releases), open it and drag
the app to `/Applications`. The build is signed with Developer ID and notarized by
Apple.

## Build from source

The generated `PerfectWhisper.xcodeproj` is part of the repository.

**Xcode:** open the project, pick the `PerfectWhisper` scheme, press ⌘R.

**Terminal:**

```sh
make build     # build
make run       # build and run from .build
make install   # build, copy to /Applications and launch
make clean     # remove build artifacts
```

If `project.yml` changed, run `make project` first to regenerate the Xcode project.

The project uses ad-hoc signing by default, so no developer team is required.
To keep permissions stable across rebuilds, select your team in
Xcode → Signing & Capabilities. Release builds take the team from an environment
variable:

```sh
DEVELOPMENT_TEAM=XXXXXXXXXX ./scripts/build-release.sh
```

### Project layout

```
Sources/
  App/        app lifecycle, dictation state machine, settings, permissions
  Audio/      microphone capture and CoreAudio device enumeration
  ASR/        WhisperKit integration, model catalog, downloads, checksums
  Input/      global hotkey and text insertion
  UI/         HUD, menu bar, settings, onboarding, about, update window
  Support/    logging and localization
Tests/        unit tests for pure logic
Resources/    Info.plist, entitlements, app icon
scripts/      release, notarization, DMG
```

See `ARCHITECTURE.md` for details.

## First run

1. Grant **Microphone** access — required for recording.
2. Grant **Accessibility** — required for the global hotkey and for inserting text
   into other apps. Without it the app still works, but the recognized text goes to
   the clipboard and you paste it yourself with ⌘V.
3. Download a model in Settings → Model (`large-v3-turbo`, about 1.6 GB).

## Usage

- **Left click** the menu bar icon to start or stop dictation.
- **Right click** for the menu: microphone, insertion mode, model, settings.
- **Hotkey** (default: double tap of right Command) starts and stops recording.
  A key combination can be configured in settings.

### Model formats

The app needs a **Core ML** Whisper bundle: a folder containing
`AudioEncoder.mlmodelc`, `TextDecoder.mlmodelc`, `MelSpectrogram.mlmodelc` and
`config.json`. A `ggml-*.bin` file from `whisper.cpp` is a different format and is
not supported, even for the same model.

Models are stored in `~/Library/Application Support/PerfectWhisper/Models`.
Every downloaded weight file is verified against the SHA-256 published by
Hugging Face; a corrupted file is deleted and the download fails.

### Microphone

- **Automatic** follows the system default input: take the headphones off and
  recording moves to the built-in microphone.
- **Explicit** always records from the selected device. This keeps Bluetooth
  headphones in A2DP, so music quality is preserved.
- If the selected device disappears, the app falls back to the system default.

### Insertion modes

- **Type character by character** — default; text arrives as keystrokes, which is
  what editors and terminals expect.
- **Paste (⌘V), restore clipboard** — fast, but some apps treat it as a paste; the
  previous clipboard contents are restored afterwards.
- **Clipboard only** — nothing is typed; a card shows what was copied.

### Language and prompt

Auto-detection uses the same multilingual model as `whisper.cpp`. The initial
prompt is optional: it can help with rare names and product terms, but a list of
English words can also bias Russian speech — leave it empty unless you need
specific terms.

## Updates

The app checks GitHub Releases once a day and from the menu
(**Check for Updates…**). To point it at another repository, set
`PWUpdateProject` (and optionally `PWUpdateProvider`: `github` or `gitlab`) in
`project.yml`, or override at runtime:

```sh
defaults write com.kt315.perfectwhisper update.project -string "owner/repo"
```

A release must have a tag like `v1.0.1` and a `.dmg` asset attached.

## Privacy

- Audio is captured in memory and never written to disk or uploaded.
- Network is used only to download models from Hugging Face and to check releases.
- No telemetry, analytics or accounts.
- Logging is **disabled in release builds** — no events and no dictated text are
  written. Only Debug builds write to
  `~/Library/Application Support/PerfectWhisper/Logs/app.log`.

## Debugging

Diagnostic flags exist **only in Debug builds**; the release binary contains just
the menu bar app and its windows.

| Flag | Purpose |
|---|---|
| `--transcribe <file>` | transcribe an audio file without UI and print timings |
| `--devices` | list microphones visible to the app |
| `--devices-all` | list all CoreAudio devices, including hidden ones |
| `--login-item on\|off\|status` | inspect launch-at-login state |

```sh
./.build/Build/Products/Debug/PerfectWhisper.app/Contents/MacOS/PerfectWhisper \
    --transcribe ~/Desktop/test.wav
```

## Signing and permissions

Ad-hoc builds (`CODE_SIGN_IDENTITY = "-"`) work, but macOS may treat each rebuild
as a new app and reset Accessibility. Release builds use Developer ID, hardened
runtime and notarization; see `docs/RELEASE.md`.

## License

MIT. See `LICENSE`.
