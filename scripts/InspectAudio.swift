import AppKit
import CoreAudio

// Read-only diagnostic. Prints metadata, never samples audio or changes devices.
@main struct InspectAudio {
    static func main() {
        do { try inspect() }
        catch {
            FileHandle.standardError.write(Data("Conch diagnostic: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
    static func inspect() throws {
        let output = try HAL.value(HAL.system, kAudioHardwarePropertyDefaultOutputDevice, default: AudioObjectID(0))
        print("Default output:", output, try HAL.string(output, kAudioObjectPropertyName))
        for scope in [kAudioObjectPropertyScopeInput, kAudioObjectPropertyScopeOutput] {
            for stream in try HAL.objects(output, kAudioDevicePropertyStreams, scope: scope) {
                let f = try HAL.format(stream)
                print("Stream", stream, "scope", scope, "rate", f.mSampleRate, "channels", f.mChannelsPerFrame, "bits", f.mBitsPerChannel, "flags", f.mFormatFlags)
            }
        }
        let objects = try HAL.objects(HAL.system, kAudioHardwarePropertyProcessObjectList)
        print("HAL process count:", objects.count)
        for object in objects {
            if let c = ProcessResolver.resolve(object, apps: NSWorkspace.shared.runningApplications) {
                print("Resolved:", c.owner.localizedName ?? "Unknown", "PID", c.pid, "object", c.object, "active", c.active, "outputs", c.devices.sorted())
            }
        }
    }
}
