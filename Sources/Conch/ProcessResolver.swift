import AppKit
import CoreAudio
import Darwin

struct AudioClient {
    let object: AudioObjectID
    let pid: pid_t
    let owner: NSRunningApplication
    let active: Bool
    let devices: Set<AudioObjectID>
    var session: AppSessionID {
        AppSessionID(pid: owner.processIdentifier, launchDate: owner.launchDate ?? .distantPast)
    }
}

protocol ProcessMetadataProviding {
    func responsiblePID(for pid: pid_t) -> pid_t?
    func parentPID(for pid: pid_t) -> pid_t?
    func executablePath(for pid: pid_t) -> String?
}

/// Optional undocumented macOS ownership SPI. This independently implemented
/// lookup is isolated here so public metadata remains the fallback;
/// no binary link dependency or guessed owner is introduced when it is absent.
private enum ProcessResponsibility {
    typealias Lookup = @convention(c) (pid_t) -> pid_t
    static let lookup: Lookup? = {
        guard
            let symbol = dlsym(
                UnsafeMutableRawPointer(bitPattern: -2),
                "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(symbol, to: Lookup.self)
    }()
}
struct SystemProcessMetadata: ProcessMetadataProviding {
    func responsiblePID(for pid: pid_t) -> pid_t? {
        guard let lookup = ProcessResponsibility.lookup else { return nil }
        let result = lookup(pid)
        return result > 1 ? result : nil
    }
    func parentPID(for pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        guard
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
                == MemoryLayout<proc_bsdinfo>.size
        else { return nil }
        return info.pbi_ppid > 1 ? pid_t(info.pbi_ppid) : nil
    }
    func executablePath(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : nil
    }
}
struct RunningAppIdentity: Equatable {
    let session: AppSessionID
    let bundleID: String?
    let bundlePath: String?
    var pid: pid_t { session.pid }
}

enum ProcessOwnershipResolver {
    static func owner(
        of pid: pid_t, bundleID: String?, apps: [RunningAppIdentity],
        metadata: ProcessMetadataProviding
    ) -> RunningAppIdentity? {
        func direct(_ candidate: pid_t) -> RunningAppIdentity? {
            apps.first { $0.pid == candidate }
        }
        func ancestor(_ start: pid_t) -> RunningAppIdentity? {
            var current = start
            var visited = Set<pid_t>()
            for _ in 0..<32 {
                guard current > 1, visited.insert(current).inserted else { return nil }
                if let app = direct(current) { return app }
                guard let parent = metadata.parentPID(for: current) else { return nil }
                current = parent
            }
            return nil
        }
        guard pid > 1 else { return nil }
        if let app = direct(pid) { return app }
        if let responsible = metadata.responsiblePID(for: pid), let app = ancestor(responsible) {
            return app
        }
        if let app = ancestor(pid) { return app }
        if let bundleID, !bundleID.isEmpty {
            let matches = apps.filter { $0.bundleID == bundleID }
            if matches.count == 1 { return matches[0] }
        }
        if let path = metadata.executablePath(for: pid),
            let bundle = Ownership.ownerPath(
                executable: path, runningAppPaths: apps.compactMap(\.bundlePath)),
            apps.filter({ $0.bundlePath == bundle }).count == 1
        {
            return apps.first { $0.bundlePath == bundle }
        }
        return nil
    }
}

enum ProcessResolver {
    static func resolve(
        _ object: AudioObjectID, apps: [NSRunningApplication],
        metadata: ProcessMetadataProviding = SystemProcessMetadata()
    ) -> AudioClient? {
        guard let pid = try? HAL.value(object, kAudioProcessPropertyPID, default: pid_t(0)),
            pid != getpid()
        else { return nil }
        let visible = apps.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != getpid()
        }
        let candidates = visible.map {
            RunningAppIdentity(
                session: AppSessionID(
                    pid: $0.processIdentifier, launchDate: $0.launchDate ?? .distantPast),
                bundleID: $0.bundleIdentifier, bundlePath: $0.bundleURL?.path)
        }
        let bundleID = try? HAL.string(object, kAudioProcessPropertyBundleID)
        guard
            let identity = ProcessOwnershipResolver.owner(
                of: pid, bundleID: bundleID, apps: candidates, metadata: metadata),
            let owner = visible.first(where: { $0.processIdentifier == identity.pid })
        else { return nil }
        let active =
            (try? HAL.value(object, kAudioProcessPropertyIsRunningOutput, default: UInt32(0))) == 1
        let devices = Set(
            (try? HAL.objects(
                object, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput)) ?? []
        )
        return AudioClient(object: object, pid: pid, owner: owner, active: active, devices: devices)
    }
}
