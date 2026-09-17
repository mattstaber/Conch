import CoreAudio
import Foundation
import Testing

@testable import Conch

private final class ObservationToken {}
private final class VolumeBackend: OutputVolumeBackend {
    var device: AudioObjectID = 50
    var values: [AudioObjectPropertySelector: Float32] = [:]
    var writableKeys = Set<AudioObjectPropertySelector>()
    var isMuted = false
    var callbacks: [AudioObjectPropertySelector: () -> Void] = [:]
    var writes = 0
    var failWrites = false
    func defaultOutput() throws -> AudioObjectID { device }
    func name(_ device: AudioObjectID) -> String { "Output \(device)" }
    func scalar(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Float32? {
        values[selector]
    }
    func muted(_ device: AudioObjectID) -> Bool { isMuted }
    func writable(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        writableKeys.contains(selector)
    }
    func writeScalar(
        _ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: Float32
    ) throws {
        if failWrites { throw AudioFailure(message: "Device disconnected") }
        values[selector] = value
        writes += 1
    }
    func writeMute(_ device: AudioObjectID, _ value: Bool) throws { isMuted = value }
    func observe(
        _ device: AudioObjectID, _ selector: AudioObjectPropertySelector,
        _ changed: @escaping () -> Void
    ) throws -> AnyObject {
        callbacks[selector] = changed
        return ObservationToken()
    }
}
@Test func volumeStepsAndSymbols() {
    #expect(VolumeControl.stepped(0.98, direction: 1) == 1)
    #expect(VolumeControl.stepped(0.02, direction: -1) == 0)
    #expect(abs(VolumeControl.stepped(0.5, direction: 1) - 0.55) < 0.00001)
    #expect(VolumeControl.symbol(volume: 0.7, muted: true) == "speaker.slash.fill")
    #expect(VolumeControl.symbol(volume: 0, muted: false) == "speaker.slash.fill")
    #expect(VolumeControl.symbol(volume: 0.2, muted: false) == "speaker.wave.1.fill")
    #expect(VolumeControl.symbol(volume: 0.5, muted: false) == "speaker.wave.2.fill")
    #expect(VolumeControl.symbol(volume: 0.9, muted: false) == "speaker.wave.3.fill")
    var app = VolumeState(volume: 0.5, isMuted: true)
    app.setVolume(VolumeControl.stepped(app.volume, direction: 1))
    #expect(app.isMuted && app.effectiveGain == 0 && abs(app.volume - 0.55) < 0.00001)
}
@Test @MainActor func masterVolumePreferenceAndUnmute() {
    let backend = VolumeBackend()
    let preferred = OutputVolumeModel.selectors[0]
    let fallback = OutputVolumeModel.selectors[1]
    backend.values = [preferred: 0.4, fallback: 0.3]
    backend.writableKeys = [preferred, fallback, kAudioDevicePropertyMute]
    backend.isMuted = true
    let model = OutputVolumeModel(backend: backend)
    model.start()
    #expect(model.canAdjust && abs(model.volume! - 0.4) < 0.00001)
    model.step(1)
    #expect(abs(backend.values[preferred]! - 0.45) < 0.00001)
    #expect(backend.values[fallback] == 0.3 && !backend.isMuted)
    model.setVolume(0)
    #expect(model.isMuted && backend.isMuted && model.volume == 0)
    model.setVolume(0.1)
    #expect(!model.isMuted && !backend.isMuted)
    model.stop()
}
@Test @MainActor func scalarFallbackAndFixedOutput() {
    let backend = VolumeBackend()
    let fallback = OutputVolumeModel.selectors[1]
    backend.values = [fallback: 0.6]
    backend.writableKeys = [fallback]
    let model = OutputVolumeModel(backend: backend)
    model.start()
    model.setVolume(0.2)
    #expect(backend.values[fallback] == 0.2)
    backend.writableKeys = []
    model.refreshProperties()
    model.setVolume(0.8)
    #expect(!model.canAdjust && backend.writes == 1 && backend.values[fallback] == 0.2)
    backend.values = [:]
    model.refreshProperties()
    #expect(model.volume == nil && !model.canAdjust)
}
@Test @MainActor func externalChangesAndDeviceSwitchAreObserved() async {
    let backend = VolumeBackend()
    let key = OutputVolumeModel.selectors[0]
    backend.values[key] = 0.2
    backend.writableKeys = [key]
    let model = OutputVolumeModel(backend: backend)
    model.start()
    backend.values[key] = 0.8
    backend.isMuted = true
    backend.callbacks[key]?()
    await Task.yield()
    #expect(abs(model.volume! - 0.8) < 0.00001 && model.isMuted)
    backend.device = 51
    backend.values = [:]
    backend.callbacks[kAudioHardwarePropertyDefaultOutputDevice]?()
    await Task.yield()
    #expect(model.name == "Output 51" && model.volume == nil && !model.canAdjust)
}
@Test @MainActor func failedHardwareWriteDoesNotPretendSuccess() {
    let backend = VolumeBackend()
    let key = OutputVolumeModel.selectors[0]
    backend.values[key] = 0.3
    backend.writableKeys = [key]
    backend.failWrites = true
    let model = OutputVolumeModel(backend: backend)
    model.start()
    model.setVolume(0.9)
    #expect(model.error != nil && abs(model.volume! - 0.3) < 0.00001)
}
