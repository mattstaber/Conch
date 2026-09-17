import CoreAudio
import Foundation
import Realtime

/// One app's process group, one hardware output and one clock. Original audio is
/// suppressed only while reading this tap. Stop IO before freeing callback memory.
final class AudioRoute {
    private var tap: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var io: AudioDeviceIOProcID?
    private var render: OpaquePointer?
    private var observations: [HALObservation] = []
    let processes: Set<AudioObjectID>
    let output: AudioObjectID
    var failure: Bool { render.map { ConchRenderFailed($0) } ?? true }
    var ticks: UInt64 { render.map { ConchRenderTicks($0) } ?? 0 }
    init(
        processes: Set<AudioObjectID>, output: AudioObjectID, state: VolumeState, metering: Bool,
        invalidated: @escaping () -> Void
    ) throws {
        self.processes = processes
        self.output = output
        do {
            let streams = try HAL.objects(
                output, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
            guard streams.count == 1 else {
                throw AudioFailure(
                    message: "This output has multiple streams. Direct playback is unchanged.")
            }
            let hardwareFormat = try HAL.format(streams[0])
            try HAL.validate(hardwareFormat)
            let uid = try HAL.string(output, kAudioDevicePropertyDeviceUID)
            let description = CATapDescription(
                processes: Array(processes), deviceUID: uid, stream: 0)
            description.name = "Conch App Audio"
            description.isPrivate = true
            description.muteBehavior = .mutedWhenTapped
            description.isProcessRestoreEnabled = false
            try HAL.check(AudioHardwareCreateProcessTap(description, &tap), "Create app audio tap")
            let format = try HAL.value(
                tap, kAudioTapPropertyFormat, default: AudioStreamBasicDescription())
            try HAL.validate(format)
            guard format.mChannelsPerFrame == hardwareFormat.mChannelsPerFrame,
                format.mSampleRate == hardwareFormat.mSampleRate
            else {
                throw AudioFailure(
                    message:
                        "The tap and output formats do not match. Direct playback is unchanged.")
            }
            let tapUID = try HAL.string(tap, kAudioTapPropertyUID)
            let composition: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Conch Private App Mixer",
                kAudioAggregateDeviceUIDKey: "dev.conch.route.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceMainSubDeviceKey: uid,
                kAudioAggregateDeviceSubDeviceListKey: [
                    [kAudioSubDeviceUIDKey: uid, kAudioSubDeviceInputChannelsKey: 0]
                ],
                kAudioAggregateDeviceTapListKey: [
                    [kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]
                ],
            ]
            try HAL.check(
                AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregate),
                "Create private audio route")
            // Reject extra inputs rather than accidentally processing a hardware mic.
            let inputs = try HAL.objects(
                aggregate, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
            let outputs = try HAL.objects(
                aggregate, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
            guard inputs.count == 1, outputs.count == 1 else {
                throw AudioFailure(
                    message:
                        "The output exposes an unsupported aggregate layout. Direct playback is unchanged."
                )
            }
            for stream in inputs + outputs {
                let f = try HAL.format(stream)
                try HAL.validate(f)
                guard f.mSampleRate == format.mSampleRate,
                    f.mChannelsPerFrame == format.mChannelsPerFrame
                else {
                    throw AudioFailure(
                        message: "The audio route changed format during setup. Try again.")
                }
            }
            guard let context = ConchRenderCreate(format.mSampleRate, state.effectiveGain) else {
                throw AudioFailure(message: "Unable to allocate realtime audio state.")
            }
            render = context
            ConchRenderSetMetering(context, metering)
            try HAL.check(ConchRenderInstall(aggregate, context, &io), "Create audio callback")
            for stream in streams + inputs + outputs {
                observations.append(
                    try HALObservation(
                        stream, kAudioStreamPropertyVirtualFormat, changed: invalidated))
            }
            observations.append(
                try HALObservation(output, kAudioDevicePropertyDeviceIsAlive, changed: invalidated))
            observations.append(
                try HALObservation(
                    output, kAudioDevicePropertyNominalSampleRate, changed: invalidated))
            try HAL.check(
                AudioDeviceStart(aggregate, io),
                "Start app audio (check System Audio Recording permission)")
        } catch {
            stop()
            throw error
        }
    }
    func setState(_ state: VolumeState) {
        if let render { ConchRenderSetGain(render, state.effectiveGain) }
    }
    func setMetering(_ enabled: Bool) { if let render { ConchRenderSetMetering(render, enabled) } }
    func peak() -> Float { render.map { ConchRenderTakePeak($0) } ?? 0 }
    func stop() {
        observations.removeAll()
        if let io {
            AudioDeviceStop(aggregate, io)
            AudioDeviceDestroyIOProcID(aggregate, io)
        }
        io = nil
        if aggregate != 0 {
            AudioHardwareDestroyAggregateDevice(aggregate)
            aggregate = 0
        }
        if tap != 0 {
            AudioHardwareDestroyProcessTap(tap)
            tap = 0
        }
        if let render { ConchRenderDestroy(render) }
        render = nil
    }
    deinit { stop() }
}
