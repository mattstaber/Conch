# macOS 27 feasibility investigation

Investigated 2026-09-16, macOS 27.0 (26A428), Command Line Tools Swift 6.4,
installed MacOSX27.0.sdk. Full Xcode is not installed. Research preceded engine implementation.

## Findings and decision

| Question | Public API finding / decision |
| --- | --- |
| Enumerate audio clients? | `kAudioHardwarePropertyProcessObjectList`; process PID, bundle ID, devices, running-input/output properties. Output activity means an active stream, not proof of nonzero samples. Resolve clients to running user-facing apps. |
| Independent gain? | No process gain property in SDK AudioHardware.h process selectors. Use a private process tap + private aggregate device, multiply samples and replay. Device volume controls are not per-app controls. |
| Mute? | `CATapMutedWhenTapped` suppresses original output while reading; callback gain zero mutes replay. Saved slider and mute are separate. |
| Meter? | Measure transient float samples already passing through the mixer. No extra recording or disk audio. Meter indicates post-gain tap samples, not acoustic loudness or attenuation later in the OS. |
| FaceTime cause? | Apple identifies FaceTime as a user of voice processing. Voice processing ducks other audio to aid intelligibility. Bluetooth call profile changes can also change perceived quality/loudness and are a separate effect. |
| Disable another app's ducking? | No public cross-process setter found. `kAUVoiceIOProperty_OtherAudioDuckingConfiguration` is a property on the caller's voice-processing Audio Unit. Its minimum setting is not documented as zero ducking. Setting it on our own unit cannot configure FaceTime. Deprecated `DuckNonVoiceAudio` explicitly warns that disabling it may be removed. |
| Detect calls / compensate? | Running input/output is only a heuristic: it is not call state, voice activity or ducking gain. No documented system ducking gain/timing signal found. Automatic inverse gain would confuse quiet content with attenuation, may clip, and may overshoot on call end. Not implemented. |
| Tap position? | Public tap contract captures outgoing process audio. It does not promise a placement before/after all voice-processing attenuation, nor exempt replay from ducking. Do not claim a tap defeats ducking. Requires controlled live-call measurement. |
| Driver/helper? | Process taps and an in-process private aggregate suffice for gain. No installed virtual driver, Audio Server Plug-In, privileged helper or system extension. A driver adds routing/installation complexity without a documented ducking bypass guarantee. |
| Permissions? | System Audio Recording via `NSAudioCaptureUsageDescription`, requested by starting the tap. No private TCC APIs. No screen frames, microphone capture, microphone gain changes or Accessibility permission. |
| Distribution? | Public APIs; normal Developer ID hardened runtime signing/notarization path. No SIP changes. Actual notarization requires the owner's signing credentials and distribution testing. |

## Implementation boundary

Normal build provides attenuation (0–1), independent mute, grouping and metering.
It does **not** promise to prevent FaceTime ducking. FaceTime volume is controllable
only if its audible streams can be resolved to FaceTime and captured by public taps.
Protected or system-owned call streams may not be accessible. Unknown daemons are
not guessed into a FaceTime row. Call reliability and echo cancellation must be
verified manually before recommending routing FaceTime during calls.

Initial route support is deliberately validated: single-stream mono/stereo native
32-bit float PCM at matching sample rates. Unsupported layouts fail open to direct
playback, with a visible error. No microphone channel is intentionally opened.
Device changes tear down routing, refresh object IDs and rebuild from saved state;
a brief direct-audio interval is possible. This is not a system-wide persistent mute.

## Primary sources

- [Apple: Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps): permission, creation, aggregate input and tap description mutation.
- [Apple: CATapMuteBehavior](https://developer.apple.com/documentation/coreaudio/catapmutebehavior): direct-output suppression semantics.
- [Apple WWDC23: What's new in voice processing](https://developer.apple.com/videos/play/wwdc2023/10235/): FaceTime use, other-audio classification, ducking levels and advanced ducking.
- [Apple: voiceProcessingOtherAudioDuckingConfiguration](https://developer.apple.com/documentation/avfaudio/avaudioinputnode/voiceprocessingotheraudioduckingconfiguration): per-node configuration.
- Installed SDK `CoreAudio.framework/Versions/A/Headers/AudioHardware.h`, process properties (lines 1943–1979), aggregate and subdevice keys; `CATapDescription.h`; `AudioHardwareTapping.h`.
- Installed SDK `AudioToolbox.framework/Versions/A/Headers/AudioUnitProperties.h`, lines 2683–2745.

Absence of a documented API is a bounded research conclusion, not a claim about
Apple's private implementation. Live device/call validation is tracked separately.

## Direct experiment update

After Xcode 27 became available, the native project and hosted tests built and ran.
On the MacBook Pro speakers (48 kHz stereo float32), QuickTime's synthetic reference
was successfully tapped, attenuated, muted and restored by the production callback.
Recorded diagnostics were peak **numbers**, not audio. The measured half-gain peak
was exactly half the full-gain peak within floating-point precision. This validates
the chosen no-driver mixer path on that route; it does not establish where FaceTime
attenuation occurs. See Validation.md for measured values and untested hardware.
