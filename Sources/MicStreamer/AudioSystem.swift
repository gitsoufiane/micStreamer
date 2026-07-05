import AppKit
import AudioToolbox
import CoreAudio
import Foundation

struct AudioDevice: Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let hasInput: Bool
    let hasOutput: Bool
}

struct AudioProcess: Equatable {
    let id: AudioObjectID
    let bundleID: String
    let name: String
}

enum AudioSystemError: LocalizedError {
    case coreAudio(OSStatus, String)
    case missingDevice(String)

    var errorDescription: String? {
        switch self {
        case .coreAudio(let status, let action):
            return "CoreAudio failed to \(action). OSStatus: \(status)."
        case .missingDevice(let message):
            return message
        }
    }
}

struct MessageError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

enum AudioSystem {
    static let systemTapAggregateName = "MicStreamer System Tap"
    static let systemTapAggregateUID = "app.micstreamer.system-tap"

    static func devices() throws -> [AudioDevice] {
        let ids = try objectList(selector: kAudioHardwarePropertyDevices)
        return ids.compactMap { id in
            guard let name = try? stringProperty(id, kAudioObjectPropertyName),
                  let uid = try? stringProperty(id, kAudioDevicePropertyDeviceUID) else {
                return nil
            }
            return AudioDevice(
                id: id,
                uid: uid,
                name: name,
                hasInput: hasStreams(id, scope: kAudioDevicePropertyScopeInput),
                hasOutput: hasStreams(id, scope: kAudioDevicePropertyScopeOutput)
            )
        }
    }

    static func device(id: AudioObjectID) throws -> AudioDevice {
        guard let device = try devices().first(where: { $0.id == id }) else {
            throw AudioSystemError.missingDevice("Audio device was not found.")
        }
        return device
    }

    static func inputDevices() throws -> [AudioDevice] {
        try devices()
            .filter(\.hasInput)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func outputDevices() throws -> [AudioDevice] {
        try devices()
            .filter(\.hasOutput)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func defaultInputDeviceID() throws -> AudioObjectID {
        try defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice, action: "read default input")
    }

    static func blackHoleOutputDevice() throws -> AudioDevice {
        guard let device = try outputDevices().first(where: isBlackHole) else {
            throw AudioSystemError.missingDevice("BlackHole 2ch output was not found.")
        }
        return device
    }

    static func destroySystemTapAggregateIfExists() throws {
        for device in try outputDevices().filter(isSystemTapAggregate) {
            try check(AudioHardwareDestroyAggregateDevice(device.id), "destroy \(systemTapAggregateName)")
        }
    }

    static func audioProcesses() throws -> [AudioProcess] {
        try objectList(selector: kAudioHardwarePropertyProcessObjectList).compactMap { id in
            guard let pid = try? pidProperty(id, kAudioProcessPropertyPID),
                  let bundleID = try? stringProperty(id, kAudioProcessPropertyBundleID),
                  !bundleID.isEmpty else {
                return nil
            }
            let appName = NSRunningApplication(processIdentifier: pid)?.localizedName
            return AudioProcess(id: id, bundleID: bundleID, name: appName ?? bundleID)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func processObjectID(pid: pid_t) throws -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var processID = AudioObjectID(kAudioObjectUnknown)
        var qualifier = pid
        var size = UInt32(MemoryLayout<AudioObjectID>.stride)
        let status = withUnsafePointer(to: &qualifier) { qualifierPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<pid_t>.stride),
                qualifierPointer,
                &size,
                &processID
            )
        }
        try check(status, "translate process ID")
        return processID == kAudioObjectUnknown ? nil : processID
    }

    static func tapUID(_ tapID: AudioObjectID) throws -> String {
        try stringProperty(tapID, kAudioTapPropertyUID)
    }

    static func setCurrentDevice(_ id: AudioDeviceID, on unit: AudioUnit?, action: String) throws {
        guard let unit else {
            throw MessageError("CoreAudio failed to \(action): missing audio unit.")
        }

        var deviceID = id
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.stride)
        )
        guard status == noErr else {
            throw MessageError("CoreAudio failed to \(action). OSStatus: \(status).")
        }
    }

    static func isBlackHole(_ device: AudioDevice) -> Bool {
        device.name.localizedCaseInsensitiveContains("blackhole") ||
            device.uid.localizedCaseInsensitiveContains("blackhole")
    }

    private static func isSystemTapAggregate(_ device: AudioDevice) -> Bool {
        device.uid == systemTapAggregateUID || device.name == systemTapAggregateName
    }

    private static func objectList(selector: AudioObjectPropertySelector) throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        try check(
            AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size),
            "read object list size"
        )

        let count = Int(size) / MemoryLayout<AudioObjectID>.stride
        var ids = [AudioObjectID](repeating: 0, count: count)
        try check(
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids),
            "read object list"
        )
        return ids
    }

    private static func stringProperty(
        _ id: AudioObjectID,
        _ selector: AudioObjectPropertySelector
    ) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.stride)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        try check(status, "read object string")
        return value as String
    }

    private static func pidProperty(
        _ id: AudioObjectID,
        _ selector: AudioObjectPropertySelector
    ) throws -> pid_t {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = pid_t(0)
        var size = UInt32(MemoryLayout<pid_t>.stride)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        try check(status, "read process ID")
        return value
    }

    private static func defaultDeviceID(
        selector: AudioObjectPropertySelector,
        action: String
    ) throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.stride)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &id
        )
        try check(status, action)
        return id
    }

    private static func hasStreams(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(id, &address) else { return false }
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    static func check(_ status: OSStatus, _ action: String) throws {
        guard status == noErr else { throw AudioSystemError.coreAudio(status, action) }
    }
}
