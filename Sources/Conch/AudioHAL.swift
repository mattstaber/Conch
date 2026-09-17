import CoreAudio
import Foundation

struct AudioFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
enum HAL {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static func address(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else {
            throw AudioFailure(message: "\(operation) (Core Audio \(status)).")
        }
    }
    static func value<T: BitwiseCopyable>(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, default initial: T,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) throws -> T {
        var a = address(selector, scope)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        try check(
            AudioObjectGetPropertyData(object, &a, 0, nil, &size, &value), "Read audio property")
        return value
    }
    static func objects(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) throws -> [AudioObjectID] {
        var a = address(selector, scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &a, 0, nil, &size), "Read audio list size")
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        if size > 0 {
            try ids.withUnsafeMutableBytes {
                try check(
                    AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0.baseAddress!),
                    "Read audio list")
            }
        }
        return ids
    }
    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws
        -> String
    {
        var a = address(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var result: Unmanaged<CFString>?
        try check(AudioObjectGetPropertyData(object, &a, 0, nil, &size, &result), "Read audio name")
        return (result?.takeRetainedValue() as String?) ?? ""
    }
    static func format(_ stream: AudioObjectID) throws -> AudioStreamBasicDescription {
        try value(stream, kAudioStreamPropertyVirtualFormat, default: AudioStreamBasicDescription())
    }
    static func validate(_ format: AudioStreamBasicDescription) throws {
        guard format.mFormatID == kAudioFormatLinearPCM,
            format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
            format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
            format.mBitsPerChannel == 32, (1...2).contains(format.mChannelsPerFrame),
            format.mSampleRate > 0,
            format.mBytesPerFrame == 4
                * (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
                    ? 1 : format.mChannelsPerFrame)
        else {
            throw AudioFailure(
                message:
                    "This output needs a mono or stereo 32-bit float PCM stream. Direct playback is unchanged."
            )
        }
    }
}

/// Retains the exact block and queue required to remove a HAL listener.
final class HALObservation {
    let object: AudioObjectID
    var address: AudioObjectPropertyAddress
    let block: AudioObjectPropertyListenerBlock
    init(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        changed: @escaping () -> Void
    ) throws {
        self.object = object
        address = HAL.address(selector, scope)
        block = { _, _ in changed() }
        try HAL.check(
            AudioObjectAddPropertyListenerBlock(object, &address, .main, block),
            "Observe audio changes")
    }
    deinit { AudioObjectRemovePropertyListenerBlock(object, &address, .main, block) }
}
