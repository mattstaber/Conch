import CoreAudio
import Foundation
import Testing

@testable import Conch

@Test func mutePreservesVolume() {
    var state = VolumeState(volume: 0.72)
    state.isMuted = true
    #expect(state.volume == 0.72)
    #expect(state.effectiveGain == 0)
    state.setVolume(0.43)
    #expect(state.effectiveGain == 0)
    state.isMuted = false
    #expect(abs(state.effectiveGain - 0.43) < 0.0001)
}
@Test func gainIsBounded() {
    var state = VolumeState()
    state.setVolume(-2)
    #expect(state.volume == 0)
    state.setVolume(3)
    #expect(state.volume == 1)
    state.setVolume(.nan)
    #expect(state.effectiveGain == 0)
    #expect(VolumeState(volume: .infinity).effectiveGain == 0)
}
@Test func helperGroupingUsesPathBoundary() {
    let paths = [
        "/Applications/Browser.app", "/Applications/Browser.app/Contents/Helpers/Helper.app",
    ]
    #expect(
        Ownership.ownerPath(
            executable: "/Applications/Browser.app/Contents/MacOS/Browser", runningAppPaths: paths)
            == paths[0])
    #expect(
        Ownership.ownerPath(
            executable:
                "/Applications/Browser.app/Contents/Helpers/Helper.app/Contents/MacOS/Helper",
            runningAppPaths: paths) == paths[1])
    #expect(
        Ownership.ownerPath(
            executable: "/Applications/Browser.app.fake/evil", runningAppPaths: paths) == nil)
    #expect(Ownership.ownerPath(executable: "/usr/libexec/daemon", runningAppPaths: paths) == nil)
}
@Test func launchIdentityRejectsPIDReuse() {
    let old = AppSessionID(pid: 100, launchDate: Date(timeIntervalSince1970: 1))
    let new = AppSessionID(pid: 100, launchDate: Date(timeIntervalSince1970: 2))
    var states = [old: VolumeState(volume: 0.2, isMuted: true)]
    states = states.filter { [new].contains($0.key) }
    #expect(states.isEmpty)
    #expect(old != new)
}
@Test func meterAttacksAndDecaysWithoutFabrication() {
    var meter = MeterEnvelope()
    meter.update(peak: 0)
    #expect(meter.level == 0)
    meter.update(peak: 1)
    #expect(meter.level == 1)
    meter.update(peak: 0)
    #expect(abs(meter.level - 0.78) < 0.0001)
    for _ in 0..<50 { meter.update(peak: 0) }
    #expect(meter.level == 0)
    meter.update(peak: .nan)
    #expect(meter.level == 0)
}
@Test func formatValidationRejectsUnsafeLayouts() throws {
    var format = AudioStreamBasicDescription()
    format.mFormatID = kAudioFormatLinearPCM
    format.mFormatFlags = kAudioFormatFlagIsFloat
    format.mBitsPerChannel = 32
    format.mChannelsPerFrame = 2
    format.mBytesPerFrame = 8
    format.mSampleRate = 48000
    try HAL.validate(format)
    format.mChannelsPerFrame = 6
    #expect(throws: AudioFailure.self) { try HAL.validate(format) }
    format.mChannelsPerFrame = 2
    format.mFormatFlags = kAudioFormatFlagIsSignedInteger
    #expect(throws: AudioFailure.self) { try HAL.validate(format) }
}

@Test func zeroVolumeMutesWithoutLosingIndependentMute() {
    var state = VolumeState(volume: 0.7)
    state.setVolume(0)
    #expect(state.isMuted)
    #expect(state.effectiveGain == 0)
    state.setVolume(0.05)
    #expect(!state.isMuted)
    state.isMuted = true
    state.setVolume(0)
    state.setVolume(0.4)
    #expect(state.isMuted)
    #expect(state.effectiveGain == 0)
    state.isMuted = false
    #expect(state.effectiveGain == 0.4)
}
