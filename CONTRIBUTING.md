# Contributing

Use macOS 27 and Xcode 27. Keep changes focused and preserve the native panel and
slider appearance. There are no third-party runtime dependencies.

## Development

- `Sources/Conch/`: AppKit/SwiftUI interface, app discovery and audio routing.
- `Sources/Realtime/`: allocation-free C audio callback and atomic state.
- `Tests/`: deterministic Swift tests, C sanitizer tests and opt-in hardware tests.
- `Resources/AppIcon.icon/`: editable layered Icon Composer source.
- `docs/`: architecture, feasibility, validation and release notes.

See [Project layout](docs/Project.md) for the source and generated folders.

Run `./scripts/test.sh` before submitting changes. It checks state, ownership,
hardware-volume behavior and the C callback under AddressSanitizer and
UndefinedBehaviorSanitizer. Ordinary tests do not capture audio. Then run
`./scripts/build.sh` to verify the native Xcode build and ad-hoc signature.

When adding Swift files, run `python3 scripts/generate-project.py` and commit the
updated Xcode project. The build/debug/live-test scripts also regenerate it.
Keep project-setting changes in the generator so regeneration preserves them.
Xcode and the scripts share `.build/Xcode/Build/Products` through the project's
`SYMROOT` setting. `./scripts/debug.sh` builds the Debug app there; use the Conch
scheme in `Conch.xcodeproj` to run with the debugger. Opening `Package.swift`
instead selects the Swift package executable, not the native application target.
Quit an existing Conch instance before switching builds.

Use `./scripts/format.sh` for consistent Swift formatting.
After changing icon layers, run `./scripts/icon.sh` with Icon Composer installed
and commit the PNG and ICNS exports along with the source.

## Live audio checks

```sh
python3 scripts/test-tone.py
# Quit Conch. Open build/synthetic-tone.wav in QuickTime and start playback.
./scripts/live-test.sh
```

The optional live test measures the production callback's gain and mute using a
synthetic reference. It never writes captured audio. Stop the test player afterward.
`./scripts/inspect-audio.sh` prints read-only process/device metadata without
creating taps. Review that output before sharing it in an issue.

Record which apps, output devices and macOS versions were actually tested. A
successful build or sample-buffer test does not prove acoustic behavior, FaceTime
call quality, Bluetooth stability or permission recovery. Use the checklist in
[Validation](docs/Validation.md).

## Audio invariants

Do not allocate, lock, log, perform file IO or call Swift object code in realtime
callbacks. Preserve independent icon mute and launch-scoped app identity. Fail
open with an error when routing is unsupported; never show a working-looking
control for audio the app cannot control. Do not add microphone processing or
speculative ducking compensation.

## Reporting a problem

Include the macOS and Conch versions, audio app, output device, reproduction steps
and any visible Conch error. Explain whether the issue also occurs after quitting
Conch. Avoid uploading private audio, call recordings, or personal diagnostic data.
