import Foundation

struct VolumeState: Equatable, Codable {
    var volume: Double = 1
    private var manuallyMuted: Bool
    // Zero volume is silent and displays as muted. Raising it restores sound,
    // unless the user independently muted the app with its icon.
    var isMuted: Bool {
        get { manuallyMuted || volume == 0 }
        set { manuallyMuted = newValue }
    }
    init(volume: Double = 1, isMuted: Bool = false) {
        self.volume = volume
        manuallyMuted = isMuted
    }
    var effectiveGain: Float { isMuted ? 0 : Float(volume.isFinite ? min(1, max(0, volume)) : 0) }
    mutating func setVolume(_ value: Double) { volume = value.isFinite ? min(1, max(0, value)) : 0 }
}
struct AppSessionID: Hashable {
    let pid: Int32
    let launchDate: Date
}
enum Ownership {
    /// Longest containing *running* app path wins; never use bundle-ID prefixes.
    static func ownerPath(executable: String, runningAppPaths: [String]) -> String? {
        runningAppPaths.filter { executable.hasPrefix($0 + "/") }.max { $0.count < $1.count }
    }
}
struct MeterEnvelope {
    var level: Double = 0
    mutating func update(peak: Float) {
        let amplitude = peak.isFinite ? max(0, Double(peak)) : 0
        let normalized = amplitude > 0 ? max(0, min(1, (20 * log10(amplitude) + 60) / 60)) : 0
        level = max(normalized, level * 0.78)
        if level < 0.002 { level = 0 }
    }
}
