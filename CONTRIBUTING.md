# Contributing

Thanks for taking a look. The project is small, so the rules are simple.

## Build and test

```sh
brew install xcodegen
xcodegen generate
open PerfectWhisper.xcodeproj     # ⌘R
make build                        # build from the terminal
xcodebuild test -project PerfectWhisper.xcodeproj \
    -scheme PerfectWhisper -destination 'platform=macOS'
```

The project is ad-hoc signed by default, so no developer team is required. To keep
permissions stable across rebuilds, pick your team in
Xcode → Signing & Capabilities.

## Welcome

- Bug fixes with reproduction steps: what you pressed, what you expected, what
  happened.
- Recognition improvements: prompts, hallucination filters, noise handling.
- Translations: adding an interface language is very welcome — add a dictionary
  to `L10n.swift`. If you change an existing string, update it for every
  language, not just yours.
- Tests for pure logic: `TextPostprocessor`, `ModelResolver`, `FileHasher`,
  `VersionCompare`, `L10n`.

## Discuss first

- Replacing the recognition engine (WhisperKit).
- Adding network services or telemetry: the app is local-only by design.
- Bringing back streaming preview: Whisper is not suitable for it (see
  `ARCHITECTURE.md`).

## Style

- Swift 6, `@MainActor` for UI, no global mutable state.
- No `try!`, `as!` or force unwraps where an error is possible.
- User-facing strings go through `L10n.t("…")` and exist in every supported
  language.
- Logs go through `Log` (compiled to no-ops in release builds).
- Comments and developer-facing strings are written in English.

## Pull requests

1. One task per PR.
2. Describe what changed and why, and include verification steps.
3. Make sure `xcodebuild test` is green and the build has no new warnings.
4. Attach a screenshot or video for interface changes.

## License

By submitting code you agree that it is distributed under the MIT license
(see `LICENSE`).
