# Validation and release checklist

Never equate a build or a synthetic PCM test with an audible hardware/call test.

## Automated

Run `scripts/test.sh`. Swift Testing covers volume/mute, path ownership, launch
identity, meter decay and rejection of unsafe formats. C tests call the actual
render callback with sample buffers under AddressSanitizer/UndefinedBehaviorSanitizer.
They verify gain, ramps, mute/restore, peaks, nonfinite samples and truncated buffers.
No audio content is recorded by tests. Generated PCM is synthetic.

`Conch.xcodeproj` contains app + hosted Swift Testing targets and a shared scheme.
The Swift package offers a Command Line Tools build/test path. `scripts/build.sh`
bundles and ad-hoc signs the release executable; Developer ID can be supplied in
`SIGNING_IDENTITY`. The CLI bundle uses an icns exported by Icon Composer; Xcode
compiles the layered `.icon` source for native current appearance variants.

## Manual test matrix (record actual results, never assume)

For each of Music, Safari/YouTube, Chrome/YouTube, QuickTime, Spotify if installed,
and Discord: start playback, confirm one correctly named/iconed row, change gain
while another app plays, mute without moving the thumb, change the thumb muted,
unmute, stop playback, quit, reopen without playback. Verify lifecycle filtering.
Use unprotected local media if a service blocks capture; record that distinction.

Test on Mac speakers, AirPods (playback and microphone/call profiles), a USB/DAC
and HDMI device. Change devices while playing and muted. Confirm values survive,
unsupported layouts show errors, direct playback returns on Quit, permission
denial, sleep/wake, unplug, and a forced app exit. Observe any direct-volume burst
on a rebuild. Confirm no persistent Conch public device remains in Audio MIDI Setup.
Test multichannel devices are rejected rather than silently downmixed.

Test dark/light, Reduce Transparency, Increase Contrast, Reduce Motion, keyboard
sliders/mute, VoiceOver labels, settings activation, menu placement with a crowded
menu bar, permission denial/retry, and Login Items from `/Applications/Conch.app`.
Measure idle CPU, active playback CPU with multiple apps, memory and callback
stalls using Activity Monitor/Instruments. No numeric performance claim before
measurement. Test for an hour on Bluetooth to expose drift/overload issues.

## FaceTime test (requires a willing call participant)

1. Play a consistent, moderate-level reference in a media app. Keep app and device
   volumes fixed and note meter and acoustic output before the call.
2. Start an actual FaceTime call; do not infer call behavior by opening the app.
3. Note ducking during silence/local speech/remote speech. Distinguish Bluetooth
   profile change from amplitude attenuation.
4. Compare direct and Conch-routed media with identical slider settings. A lower
   tap meter is compatible with pre-tap attenuation; unchanged meter and lower
   acoustic output is compatible with downstream attenuation. Neither observation
   alone identifies every stage in Apple's private pipeline.
5. If FaceTime is discovered, check its independent gain and mute without touching
   microphone settings. Verify the other participant hears no new echo, noise,
   dropouts or change in intelligibility. Verify AirPods route selection.
6. End call and check for volume jumps, route failures and normal audio recovery.

No call is initiated automatically: it would contact another person. Do not claim
actual ducking prevention; no such supported switch is implemented. If FaceTime's
stream cannot be captured, report it as unsupported rather than displaying a
working-looking control for a system daemon.

## Distribution gate

Install a signed build in Applications; complete the system audio permission
prompt and verify recovery after permission is revoked. Build/test using full
Xcode 27. Sign with an owner-provided Developer ID, submit a zip using `notarytool`,
staple, and verify Gatekeeper on a separate Mac. Do not disable SIP or Gatekeeper.
The project does not claim App Store sandbox compatibility.

## Historical results — September 16–17, 2026

The entries below record earlier runs, not verification of every subsequent edit.

Host: Apple silicon MacBook Pro, macOS 27.0 build 26A428; Xcode 27.0 build
27A266a and macOS 27 SDK. The machine initially had only selected Command Line
Tools; full Xcode setup completed during development.

| Check | Result |
| --- | --- |
| Native Xcode application build | Passed, native Icon Composer assets compiled |
| Xcode hosted Swift Testing | 17 tests passed on September 16, including live routing |
| SwiftPM tests | September 17: 17 deterministic tests passed; opt-in live test skipped |
| C callback under ASan + UBSan | Passed gain/ramp/mute/restore/peak/NaN/short buffer checks; planar-output coverage included |
| Release bundle | Built, ad-hoc hardened-runtime signature verified; approximately 2.1 MB |
| Real Core Audio discovery | MacBook speakers: 48 kHz, stereo float32; Chrome helper PIDs resolved to Google Chrome |
| Live QuickTime route test | Passed: full peak 0.019994522, half 0.009997261, muted 0, restored 0.009997261; 245 callbacks in September 16 regression |
| UI slider and independent mute | QuickTime slider remained unchanged on mute; real native icon and control shown |
| Session lifecycle | Paused player retained at 0.65; quitting removed row; idle relaunch stayed absent |
| Screenshots | Outdated September 16 screenshots were removed; current interface screenshots have not been captured |
| Chrome local fixture | Automated browser opening was blocked by the browser tool's URL policy; no workaround attempted |
| FaceTime call / echo cancellation | Not tested: needs a willing participant and acoustic/call evaluation |
| AirPods, USB/DAC, HDMI, device switching | Not exercised with physical devices |
| Music and Chrome UI sessions | Real app rows and selected gains observed in the running release app; no independent acoustic gain test |
| Safari and YouTube Music | Separate active rows verified during simultaneous playback; independent selected volume/mute, Safari quit removal and idle relaunch filtering verified September 16; independent acoustic measurement not performed |
| Spotify, Discord playback | Not validated |
| Appearance and accessibility | Light/dark inspected September 16; full accessibility, dragging, multiple displays and Spaces matrix remains unverified after user visual edits |
| Long-duration CPU/memory/drift | Not benchmarked |
| Developer ID / notarization / clean Mac | Not performed; owner credentials and distribution acceptance remain necessary |

The live test verifies samples inside the **production callback** and route setup.
It does not measure the physical speaker waveform, downstream ducking, echo
cancellation, independent simultaneous-app acoustic output or end-to-end latency.
Protected content and denied/revoked permission behavior need separate acceptance:
if an OS capture path supplies zero samples without an error, silence alone cannot
distinguish denial/protection from genuinely silent source content.

## September 17 follow-up

Preserved the user-edited VolumeSlider and panel appearance. Added deterministic
coverage for zero-volume mute, raising from zero, preserving independent icon mute,
and hardware mute at zero. Rebuilt the release bundle and verified its ad-hoc signature.
Icon Composer exported the new channel/fader groups to PNG and ICNS; the exported
image was visually inspected. No fresh live playback test was performed for this
state/icon-only follow-up. September 16 live QuickTime regression measured full
0.019994522, half 0.009997261, mute 0 and restored 0.009997261 (245 callbacks).
The undocumented ownership lookup remains in the main build, with guarded public
fallbacks; these results do not establish compatibility with every audio application.

## Public repository preparation — 2026-09-17

- Swift formatting/lint and all 17 deterministic Swift tests passed; the optional
  live test was skipped. C callback sanitizer tests passed.
- Native Release build and ad-hoc signature verification passed with the current
  icon source. This cleanup did not change the panel or slider behavior.
- The distribution ZIP was extracted locally; its app signature, executable
  permissions, bundled MIT license and SHA-256 checksum verified successfully.
- Workflow YAML and embedded shell steps were parsed locally. GitHub Actions has
  not run this workflow yet. No tag, remote push, or release was created here.
- Developer ID signing, notarization and a downloaded build on a separate Mac
  remain unverified. The default automated release is explicitly ad-hoc signed.

## Build-layout cleanup — September 17, 2026

- Removed stale local builds, obsolete screenshots, unused icon appearance PNGs,
  and local package/editor state. Retained editable icon layers, README PNG, and
  fallback ICNS; native Xcode compilation generates appearance variants.
- Native Xcode and script builds now share `.build/Xcode/Build/Products`.
  Default Xcode Debug build settings were inspected without a DerivedData override
  and resolve to that same Debug product directory.
- Fresh Debug and Release builds succeeded with native icon compilation; both
  app signatures verified. The staged release app is `build/Conch.app`.
- Python project reproducibility and C ASan/UBSan tests passed. SwiftPM and hosted
  Xcode tests each passed all 17 deterministic tests; the live audio test was skipped.
- Swift formatting, shell syntax, local documentation links, and diff whitespace
  checks passed.
- No new live audio, visual/accessibility, remote CI, notarization, or distribution
  acceptance is claimed by this cleanup. The earlier hardware results remain historical.
