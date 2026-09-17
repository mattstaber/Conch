# Architecture

## Data and control

`MixerModel` owns main-actor UI state and HAL/NSWorkspace observation lifetimes.
A process-list notification adds/removes per-process activity/device listeners.
An 80 ms coalescing delay absorbs bursts. No process scanning timer runs at idle.
Only running regular applications with an observed output stream enter the list.
A row survives stream removal until the owning app quits; launch date plus PID
prevents old volume/mute state from being attached to a reused PID.

`ProcessResolver` accepts only running regular applications. It tries direct PID,
then responsible-process identity and bounded ancestry, exact Core Audio bundle
identifier, longest containing app bundle, and original-process ancestry. Ancestry
is capped at 32 nodes with cycle detection. There is no bundle-prefix guessing or
blanket Safari ownership for WebKit. Clients are regrouped on every refresh, and
PID plus launch date determines row identity; no ownership cache survives a launch.

`ProcessMetadataProviding` isolates process queries for deterministic tests.
`SystemProcessMetadata` optionally resolves the undocumented
`responsibility_get_pid_responsible_for_pid` using `dlsym` once. This is an
independent implementation included in the main build,
informed by [Vorssaint's resolver](https://github.com/vorssaint/vorssaint-utils/blob/main/Sources/Vorssaint/Services/ResponsibleProcess.swift).
No source is imported. Missing symbols/invalid identities fall back to public
metadata. Future macOS releases may remove or change the SPI; App Store acceptance
and future compatibility are not guaranteed. Shared/unknown services stay omitted.

`VolumeState` keeps `volume` and `isMuted` separate. Muting never changes the thumb.
Slider changes while muted change the eventual unmute value. State persists for
the app's launch only; the only defaults are the two UI preferences. Remembering
volumes across launches is intentionally deferred until hardware validation.

## Audio path

```
application output -> device-specific CATapDescription (process group)
                   -> private aggregate input
                   -> C float gain + 5 ms gain ramp + optional peak
                   -> aggregate's physical output subdevice
```

Each active app gets one private tap and aggregate. The original is suppressed by
`mutedWhenTapped` while the aggregate reads the tap. There is no installed driver
and the system default output device is never changed. The physical output is the
clock source. Input channel count zero is requested for the hardware subdevice;
the resulting aggregate must expose only the tap input or routing is refused.
No microphone callbacks are created. The selected physical output must have one
mono/stereo float32 stream. Sample rates/channel counts must agree before starting.

The C callback is allocation-free, lock-free, bounded by HAL buffer sizes, and has
no Swift references, dispatch calls, logging or IO. Lock-free atomics carry gain,
meter peak, a callback counter and a format-failure flag. Gain is attenuation only,
never an inverse ducking boost. The meter reads processed samples only while the
panel is open and metering is enabled (20 Hz visual updates, immediate attack and
decaying release). The meter is not a microphone or post-speaker measurement.

A one-second watchdog exists only while routes exist; a malformed callback layout
or three missed progress checks destroys the route and reports direct playback.
It is a recovery mechanism, not a realtime guarantee. `AudioDeviceStop` and
`AudioDeviceDestroyIOProcID` stop callbacks first; the aggregate and tap are then
destroyed before freeing the C context. Setup failures unwind the same path.
Original audio can briefly play at its own gain during rebuild or recovery, even if the saved mute is true.

Default-output changes rebuild routes using the same row state. Physical stream
format, sample rate and liveness changes invalidate the route. Applications using
other outputs or more than one output are explicitly refused rather than partly
controlled. AirPods call-profile changes may temporarily yield an unsupported
format. Unsupported devices retain direct playback with an error and Retry.

## Presentation and preferences

`ConchApp` presents the mixer through SwiftUI `MenuBarExtra` with the window style.
SwiftUI and macOS own the menu-bar window presentation and background.
A stock NSSlider preserves the system Liquid Glass control appearance. A
noninteractive SwiftUI meter overlay displays activity using the native slider
layout. The visual width also scales by the selected volume, so it is an activity
indicator rather than a calibrated level display. Its timer uses common run-loop
modes during tracking. Native Settings, SF Symbol status image and NSWorkspace icons adapt to system appearance.
Background accessibility behavior is delegated to the system presentation.
Reduce Motion suppresses meter interpolation. The current meter overlay uses a white gradient; increased-contrast
acceptance remains unverified. VoiceOver
gets app-specific action labels and volume values, without visible percentages.
Rows are sorted when the panel opens; activity does not reorder controls under a
pointer. Quitting ends the process and its routes. Launch at Login uses
`SMAppService.mainApp`.

## Known design costs

One aggregate per active app is simpler to validate and isolates failed apps, but
has higher callback/device overhead than one shared multichannel mixer. Measure
several active apps before distribution. No UI meter work occurs with the panel
closed or with no routed apps; audio callbacks still must run for gain to remain effective.

All audio control uses public APIs; the ownership SPI exception is documented above.
No microphone-gain, voice-processing, ducking,
private TCC, ScreenCaptureKit, network, analytics or telemetry code exists.

## Hardware system volume

`OutputVolumeModel` is independent of per-app gain and injects an
`OutputVolumeBackend`. It prefers writable virtual main volume, then the main
scalar. A readable but nonwritable output is displayed with disabled controls.
Volume, hardware mute and default-device listeners refresh the slider and template
speaker icon. Positive writes clear supported hardware mute. There is no app-gain
substitute for unsupported system volume, and device selection stays in Sound Settings.

## Zero-volume mute and icon revision — 2026-09-17

App mute is the combination of independent icon mute and zero slider volume.
Dragging or stepping to zero displays mute immediately. Raising volume clears
zero-volume mute while preserving an explicit icon mute. Hardware volume writes
set the device mute property at zero where supported, and clear it for positive volume.
The Icon Composer source separates channel rails and fader caps into two glass
groups, with caps above the channels. The panel retains its native slider appearance.
