# Architecture

## What this is

A menu bar app: record the microphone → transcribe locally with Whisper →
insert the text into the active app. No network, no accounts, no telemetry.

The app is intentionally **not sandboxed**: `CGEventPost` into other processes and
a global `CGEventTap` are unavailable (or require exceptions App Review rejects)
in the sandbox. This is a deliberate choice in favour of automatic text insertion.

## Data flow

```
hotkey / menu bar click
        │
        ▼
DictationController  ──►  AudioCaptureEngine  ──►  [Float] 16 kHz mono
        │                        ▲                        │
        │                        │                        ▼
        │              AudioDeviceManager        WhisperKitTranscriber
        │              (CoreAudio, pin/hot-plug) (WhisperKit, ANE/Core ML)
        │                                                 │
        ▼                                                 ▼
   HUDController  ◄──── phase / level           TextPostprocessor
                                                          │
                                                          ▼
                                                   TextInserter
                                              (⌘V + clipboard restore)
```

## Modules

| File | Responsibility |
|---|---|
| `Sources/main.swift` | Entry point, early exit for a second instance, debug flags |
| `App/AppDelegate.swift` | Status item wiring, menus, windows, permissions onboarding |
| `App/DictationController.swift` | State machine: idle → recording → transcribing → idle |
| `App/Prefs.swift` | `UserDefaults` keys, defaults, insertion mode |
| `App/Permissions.swift` | Microphone and Accessibility, resets, System Settings links |
| `App/InstanceGuard.swift` | `flock`-based single-instance guard |
| `App/LoginItem.swift` | Launch at login through `SMAppService.mainApp` |
| `Audio/AudioDeviceManager.swift` | CoreAudio input enumeration, default device, hot-plug |
| `Audio/AudioCaptureEngine.swift` | `AVAudioEngine` → 16 kHz mono Float32 in memory |
| `ASR/WhisperKitTranscriber.swift` | Model loading, decoding options, transcription |
| `ASR/ModelCatalog.swift` | Variant catalog and model folder resolution |
| `ASR/ModelRepository.swift` | Facade for model state used by the UI |
| `ASR/Models/*` | Data types, Hugging Face client, disk store, downloads, tester, hashing |
| `Input/HotkeyManager.swift` | `CGEventTap` on a dedicated thread, double-tap detection |
| `Input/TextInserter.swift` | Clipboard, ⌘V, Unicode typing |
| `UI/HUD.swift` | Non-activating floating panel with timer and level meter |
| `UI/StatusMenuController.swift` | Status item and all menus |
| `UI/Settings/*` | SwiftUI settings tabs, hotkey recorder, warnings |
| `UI/OnboardingWindow.swift` | Permission checklist on first launch |
| `Update/*` | GitHub/GitLab release checks and version comparison |

## Key decisions

**WhisperKit instead of `whisper.cpp`.** Same weights, but Core ML/ANE: it does not
compete with the GPU for frames, integrates natively with Swift, and downloads
models from Hugging Face. The model stays resident in memory; otherwise every
dictation would pay for Core ML initialization.

**Audio in memory, not in a file.** A dictation clip is a few megabytes. A file
would add I/O, cleanup and a risk of leaking speech to disk.

**Device pinning.** `kAudioOutputUnitProperty_CurrentDevice` on the input node.
The reason is not only recognition quality: recording from a Bluetooth headset
switches it to HFP and degrades music playback. Pinning the built-in microphone
avoids that.

**`initial_prompt` instead of hard language switching.** Auto-detection on short
mixed-language clips is unstable. A list of terms in the prompt plus
`language=auto` performs better than fixing a single language.

**HUD as a non-activating panel.** The overlay must not take focus, otherwise ⌘V
goes to the overlay instead of the user's app.

**Hotkey tap on a dedicated thread.** A session-level event tap on the main run
loop can stall system-wide input whenever the main thread is busy (dialogs, model
loading). The tap therefore runs on its own thread and only dispatches to the main
actor.

## Concurrency

- UI and dictation state are `@MainActor`.
- The audio callback runs on an `AVAudioEngine` thread; sample storage is protected
  by `NSLock`, and the level is reported to the UI with throttling.
- Inference runs in `nonisolated async` WhisperKit methods; `WhisperKitTranscriber`
  is `@unchecked Sendable` and used strictly serially.
- The `CGEventTap` callback performs only a keycode/modifier match and dispatches
  the action to the main queue.

## Extension points

### Streaming partial text

Tried and removed. Two approaches failed on live speech:

1. **Sliding window with word timestamps.** WhisperKit returned degenerate word
   timings (all words at one point), so the "committed" text could not be frozen.
2. **VAD-based phrases.** Stable, but on long pauses the model receives silence
   and hallucinates subtitles.

Whisper is an offline model with a 30-second window; pseudo-streaming always
flickers or hallucinates. The final text is produced by a single pass over the
whole buffer, which is also what the user sees inserted.

If live text is ever needed, the right path is a separate streaming engine for
preview (for example Parakeet via FluidAudio) while keeping Whisper for the final
text.

### VAD and noise handling

Only clips shorter than 0.35 s and a list of known hallucinations are filtered.
Next steps: an energy VAD before sending audio, `noSpeechThreshold`, and a larger
hallucination list.

### LLM post-processing

Disabled by default and not needed: the model punctuates well on its own. If added,
it belongs between `TextPostprocessor` and `TextInserter`, behind an explicit
toggle that shows the added latency.

## Logging

`Log` is compiled only with the `PERFECTWHISPER_LOGGING` flag (Debug
configuration). In release builds the methods are empty stubs: no file, no
`NSLog`, no dictated text.

## Known limitations

- One app instance only; a second copy exits silently.
- The hotkey supports key combinations and double-tapped modifiers, not
  single-modifier or media keys (the microphone key needs Karabiner).
- No dictation history or statistics.
- No automatic updates; update checks open the DMG in the browser.
