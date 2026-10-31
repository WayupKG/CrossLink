# Contributing to CrossLink

Thanks for your interest! Bug reports, ideas and pull requests are all welcome.

## Reporting bugs and ideas

Open an [issue](https://github.com/WayupKG/CrossLink/issues/new/choose) and pick a template.
For bugs, the Mac and phone models, OS versions and the steps to reproduce help the most.
Security problems go through [SECURITY.md](SECURITY.md), not public issues.

## Development setup

See [Getting started](README.md#-getting-started) for building both apps.

| Part | Where | Check before a PR |
|---|---|---|
| macOS app | `macos/` | `cd macos && xcodegen generate && xcodebuild -project CrossLink.xcodeproj -scheme CrossLink build CODE_SIGNING_ALLOWED=NO` |
| Android app | `android/` | `cd android && ./gradlew assembleDebug` |
| Protocol | `PROTOCOL.md`, `tests/` | `python -m unittest discover -s tests -v` |

## Guidelines

- **The protocol is shared.** A change to the wire format must update the Swift side, the Kotlin
  side, [PROTOCOL.md](PROTOCOL.md) and the Python tests in the same pull request.
- **Design tokens match.** `macos/CrossLink/Theme.swift` and `android/.../ui/Theme.kt` hold the
  same values; change them together.
- **Respect Google Play policies.** The Android app is headed for Google Play, so no Accessibility
  or `READ_LOGS` workarounds and no hidden background clipboard reading.
- **Never log secrets or content.** No pairing keys, clipboard text or file data in logs.
- Keep pull requests focused, and describe how you tested them on real devices.

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
