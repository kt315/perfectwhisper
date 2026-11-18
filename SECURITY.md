# Security

PerfectWhisper works locally: audio never leaves the Mac and there is no telemetry.
The app does request the microphone and Accessibility, which are sensitive
permissions.

## Reporting a vulnerability

Please do not open a public issue if the problem involves:

- leaking audio or dictated text;
- bypassing model integrity checks (SHA-256);
- unsafe handling of model files;
- privilege escalation through the hotkey or text insertion.

Report it privately on GitHub, either through
[Security Advisories](https://github.com/kt315/perfectwhisper/security/advisories/new)
(the "Report a vulnerability" button on the repository's Security tab) or by
contacting [@kt315](https://github.com/kt315) directly. Include the version,
reproduction steps and, if possible, a minimal example.

We will acknowledge within 72 hours and agree on a disclosure timeline.

## Expected behaviour

- The Accessibility prompt is required for the global hotkey and text insertion.
- Models are downloaded from Hugging Face only on explicit user action.

## Supported versions

Security fixes are provided for the latest published release.
