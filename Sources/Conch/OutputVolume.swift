import AppKit
import AudioToolbox
import Combine
import CoreAudio

protocol OutputVolumeBackend {
    func defaultOutput() throws -> AudioObjectID
    func name(_ device: AudioObjectID) -> String
    func scalar(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Float32?
    func muted(_ device: AudioObjectID) -> Bool
    func writable(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool
    func writeScalar(
        _ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: Float32) throws
    func writeMute(_ device: AudioObjectID, _ value: Bool) throws
    func observe(
        _ device: AudioObjectID, _ selector: AudioObjectPropertySelector,
        _ changed: @escaping () -> Void
    ) throws -> AnyObject
}
struct HardwareOutputVolume: OutputVolumeBackend {
    func defaultOutput() throws -> AudioObjectID {
        try HAL.value(
            HAL.system, kAudioHardwarePropertyDefaultOutputDevice, default: AudioObjectID(0))
    }
    func name(_ device: AudioObjectID) -> String {
        (try? HAL.string(device, kAudioObjectPropertyName)) ?? "No output device"
    }
    func scalar(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Float32? {
        guard
            let result = try? HAL.value(
                device, selector, default: Float32(0), scope: kAudioObjectPropertyScopeOutput),
            result.isFinite
        else { return nil }
        return result
    }
    func muted(_ device: AudioObjectID) -> Bool {
        (try? HAL.value(
            device, kAudioDevicePropertyMute, default: UInt32(0),
            scope: kAudioObjectPropertyScopeOutput)) == 1
    }
    func writable(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var a = HAL.address(selector, kAudioObjectPropertyScopeOutput)
        var result = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, &a, &result) == noErr && result.boolValue
    }
    private func write<T: BitwiseCopyable>(
        _ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T
    ) throws {
        var a = HAL.address(selector, kAudioObjectPropertyScopeOutput)
        var value = initial
        try HAL.check(
            AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<T>.size), &value),
            "Change system volume")
    }
    func writeScalar(
        _ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: Float32
    ) throws { try write(device, selector, value) }
    func writeMute(_ device: AudioObjectID, _ value: Bool) throws {
        try write(device, kAudioDevicePropertyMute, UInt32(value ? 1 : 0))
    }
    func observe(
        _ device: AudioObjectID, _ selector: AudioObjectPropertySelector,
        _ changed: @escaping () -> Void
    ) throws -> AnyObject {
        try HALObservation(
            device, selector,
            scope: (device == HAL.system || selector == kAudioObjectPropertyName)
                ? kAudioObjectPropertyScopeGlobal : kAudioObjectPropertyScopeOutput,
            changed: changed)
    }
}
enum VolumeControl {
    static func clamped(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
    static func stepped(_ value: Double, direction: Double) -> Double {
        clamped(value + direction * 0.05)
    }
    static func symbol(volume: Double?, muted: Bool) -> String {
        if muted || volume == 0 { return "speaker.slash.fill" }
        guard let volume else { return "speaker.wave.2.fill" }
        if volume <= 1.0 / 3 { return "speaker.wave.1.fill" }
        if volume <= 2.0 / 3 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
@MainActor final class OutputVolumeModel: ObservableObject {
    static let selectors: [AudioObjectPropertySelector] = [
        kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyVolumeScalar,
    ]
    @Published private(set) var volume: Double?
    @Published private(set) var isMuted = false
    @Published private(set) var canAdjust = false
    @Published private(set) var name = "System output"
    @Published private(set) var error: String?
    var symbol: String { VolumeControl.symbol(volume: volume, muted: isMuted) }
    private let backend: OutputVolumeBackend
    private var device: AudioObjectID = 0
    private var selector: AudioObjectPropertySelector?
    private var systemObservation: AnyObject?
    private var deviceObservations: [AnyObject] = []
    init(backend: OutputVolumeBackend = HardwareOutputVolume()) { self.backend = backend }
    func start() {
        do {
            systemObservation = try backend.observe(
                HAL.system, kAudioHardwarePropertyDefaultOutputDevice
            ) { [weak self] in Task { @MainActor in self?.refreshDevice() } }
        } catch { self.error = error.localizedDescription }
        refreshDevice()
    }
    func stop() {
        systemObservation = nil
        deviceObservations.removeAll()
    }
    func refreshDevice() {
        deviceObservations.removeAll()
        do {
            device = try backend.defaultOutput()
            name = backend.name(device)
            refreshProperties()
            for property in Self.selectors + [kAudioDevicePropertyMute, kAudioObjectPropertyName] {
                if let observation = try? backend.observe(
                    device, property,
                    { [weak self] in Task { @MainActor in self?.refreshProperties() } })
                {
                    deviceObservations.append(observation)
                }
            }
        } catch {
            device = 0
            volume = nil
            canAdjust = false
            selector = nil
            self.error = error.localizedDescription
        }
    }
    func refreshProperties() {
        let readable = Self.selectors.compactMap { key -> (AudioObjectPropertySelector, Float32)? in
            backend.scalar(device, key).map { (key, $0) }
        }
        let choice = readable.first { backend.writable(device, $0.0) } ?? readable.first
        selector = choice?.0
        volume = choice.map { VolumeControl.clamped(Double($0.1)) }
        canAdjust = choice.map { backend.writable(device, $0.0) } ?? false
        isMuted = backend.muted(device)
        name = backend.name(device)
    }
    func setVolume(_ value: Double) {
        guard canAdjust, let selector else { return }
        do {
            let target = Float32(VolumeControl.clamped(value))
            try backend.writeScalar(device, selector, target)
            if backend.writable(device, kAudioDevicePropertyMute), isMuted != (target == 0) {
                try backend.writeMute(device, target == 0)
            }
            error = nil
            refreshProperties()
        } catch {
            self.error = error.localizedDescription
            refreshProperties()
        }
    }
    func step(_ direction: Double) {
        if let volume { setVolume(VolumeControl.stepped(volume, direction: direction)) }
    }
}
