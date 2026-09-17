import Foundation
import Testing

@testable import Conch

private struct Metadata: ProcessMetadataProviding {
    var responsible: [Int32: Int32] = [:]
    var parents: [Int32: Int32] = [:]
    var paths: [Int32: String] = [:]
    func responsiblePID(for pid: Int32) -> Int32? { responsible[pid] }
    func parentPID(for pid: Int32) -> Int32? { parents[pid] }
    func executablePath(for pid: Int32) -> String? { paths[pid] }
}
private func identity(_ pid: Int32, _ bundle: String, _ path: String, launch: Double = 1)
    -> RunningAppIdentity
{
    .init(
        session: .init(pid: pid, launchDate: Date(timeIntervalSince1970: launch)), bundleID: bundle,
        bundlePath: path)
}
private let safari = identity(100, "com.apple.Safari", "/Applications/Safari.app")
private let music = identity(
    200, "com.apple.Safari.WebApp.music", "/Users/test/Applications/YouTube Music.app")
@Test func responsibleWebKitHelpersRemainSeparate() {
    let metadata = Metadata(
        responsible: [301: 100, 302: 200, 303: 200], parents: [301: 1, 302: 1, 303: 1])
    let owners = [301, 302, 303].compactMap {
        ProcessOwnershipResolver.owner(
            of: Int32($0), bundleID: "com.apple.WebKit.GPU", apps: [safari, music],
            metadata: metadata)
    }
    #expect(owners.map(\.pid) == [100, 200, 200])
    #expect(Dictionary(grouping: owners, by: \.session).count == 2)
}
@Test func responsibleHelperCanRequireParentTraversal() {
    let metadata = Metadata(responsible: [300: 400], parents: [400: 401, 401: 200])
    #expect(
        ProcessOwnershipResolver.owner(
            of: 300, bundleID: nil, apps: [safari, music], metadata: metadata) == music)
}
@Test func absentOrInvalidSPIUsesPublicMetadata() {
    #expect(
        ProcessOwnershipResolver.owner(
            of: 300, bundleID: music.bundleID, apps: [safari, music], metadata: Metadata()) == music
    )
    let invalid = Metadata(
        responsible: [300: -1], paths: [300: "/Applications/Safari.app/Contents/Helpers/Audio"])
    #expect(
        ProcessOwnershipResolver.owner(
            of: 300, bundleID: "com.apple.WebKit.GPU", apps: [safari, music], metadata: invalid)
            == safari)
    #expect(
        ProcessOwnershipResolver.owner(
            of: 300, bundleID: nil, apps: [safari], metadata: Metadata(parents: [300: 100]))
            == safari)
}
@Test func neverGuessSharedWebKitOrAmbiguousBundleOwner() {
    #expect(
        ProcessOwnershipResolver.owner(
            of: 300, bundleID: "com.apple.WebKit.GPU", apps: [safari, music],
            metadata: Metadata(parents: [300: 1])) == nil)
    let duplicate = identity(201, music.bundleID!, music.bundlePath!)
    #expect(
        ProcessOwnershipResolver.owner(
            of: 300, bundleID: music.bundleID, apps: [music, duplicate], metadata: Metadata())
            == nil)
    #expect(
        ProcessOwnershipResolver.owner(
            of: 300, bundleID: nil, apps: [safari],
            metadata: Metadata(parents: [300: 301, 301: 300])) == nil)
    #expect(
        ProcessOwnershipResolver.owner(
            of: 300, bundleID: nil, apps: [music, duplicate],
            metadata: Metadata(paths: [300: music.bundlePath! + "/Contents/Helper"])) == nil)
}
@Test func directAppIdentityWinsAndLaunchIdentityRefreshes() {
    #expect(
        ProcessOwnershipResolver.owner(
            of: 100, bundleID: music.bundleID, apps: [safari, music],
            metadata: Metadata(responsible: [100: 200])) == safari)
    let newSafari = identity(100, safari.bundleID!, safari.bundlePath!, launch: 2)
    let resolved = ProcessOwnershipResolver.owner(
        of: 300, bundleID: nil, apps: [newSafari], metadata: Metadata(responsible: [300: 100]))
    #expect(resolved?.session == newSafari.session)
    #expect(resolved?.session != safari.session)
    #expect(
        ProcessOwnershipResolver.owner(
            of: 300, bundleID: nil, apps: [], metadata: Metadata(responsible: [300: 100])) == nil)
}
