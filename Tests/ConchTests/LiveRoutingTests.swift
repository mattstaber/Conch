import Testing
import Foundation
import AppKit
import CoreAudio
@testable import Conch

/// Opt-in hardware test. Play scripts/test-tone.py's file in QuickTime first and
/// quit all ordinary Conch instances. Does not record or save any audio samples.
@Test(.enabled(if: ProcessInfo.processInfo.environment["CONCH_LIVE_AUDIO_TEST"] == "1"))
@MainActor func liveQuickTimeGainAndMute() async throws {
    let objects = try HAL.objects(HAL.system, kAudioHardwarePropertyProcessObjectList)
    let clients = objects.compactMap { ProcessResolver.resolve($0, apps: NSWorkspace.shared.runningApplications) }
        .filter { $0.owner.bundleIdentifier == "com.apple.QuickTimePlayerX" && $0.active }
    try #require(!clients.isEmpty, "Play the quiet synthetic tone in QuickTime before this test.")
    let output = try HAL.value(HAL.system, kAudioHardwarePropertyDefaultOutputDevice, default: AudioObjectID(0))
    let route = try AudioRoute(processes: Set(clients.map(\.object)), output: output, state: VolumeState(), metering: true, invalidated: {})
    defer { route.stop() }
    func settledPeak() async throws -> Float {
        try await Task.sleep(for: .milliseconds(400))
        _ = route.peak()
        try await Task.sleep(for: .milliseconds(250))
        #expect(!route.failure)
        return route.peak()
    }
    let full = try await settledPeak()
    try #require(full > 0.001, "Capture returned silence: check permission and fixture playback.")
    route.setState(VolumeState(volume: 0.5))
    let half = try await settledPeak()
    #expect(abs(half / full - 0.5) < 0.03)
    route.setState(VolumeState(volume: 0.5, isMuted: true))
    let muted = try await settledPeak()
    #expect(muted < 0.000001)
    route.setState(VolumeState(volume: 0.5))
    let restored = try await settledPeak()
    #expect(abs(restored / full - 0.5) < 0.03)
    #expect(route.ticks > 0)
    print("Conch live route: full=\(full), half=\(half), muted=\(muted), restored=\(restored), callbacks=\(route.ticks)")
}
