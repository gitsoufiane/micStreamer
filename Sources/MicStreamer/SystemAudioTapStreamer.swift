import CoreAudio
import Foundation

enum CaptureSource: Equatable {
    case allExceptCalls
    case process(bundleID: String, name: String)

    var title: String {
        switch self {
        case .allExceptCalls:
            return "All Apps Except Calls"
        case .process(_, let name):
            return name
        }
    }
}

struct SystemAudioTapStreamerError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

@available(macOS 14.2, *)
final class SystemAudioTapStreamer {
    static let callBundleIDs: Set<String> = [
        "com.apple.FaceTime",
        "com.hnc.Discord",
        "com.hnc.DiscordCanary",
        "com.hnc.DiscordPTB",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.skype.skype",
        "com.tinyspeck.slackmacgap",
        "us.zoom.xos"
    ]

    private let queue = DispatchQueue(label: "app.micstreamer.system-tap", qos: .userInitiated)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    var isRunning: Bool {
        ioProcID != nil
    }

    func start(outputDeviceID: AudioDeviceID, source: CaptureSource) throws {
        stop()

        let outputDevice = try AudioSystem.device(id: outputDeviceID)
        let excludedIDs = try excludedProcessIDs()
        let description = try tapDescription(for: source, excludedIDs: excludedIDs)
        description.name = "MicStreamer System Audio"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        try AudioSystem.check(AudioHardwareCreateProcessTap(description, &newTapID), "create system audio tap")
        tapID = newTapID

        do {
            let tapUID = try AudioSystem.tapUID(newTapID)
            aggregateID = try createAggregate(outputDevice: outputDevice, tapUID: tapUID)
            try startLoopback(aggregateID: aggregateID)
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }

        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }

        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func tapDescription(for source: CaptureSource, excludedIDs: [AudioObjectID]) throws -> CATapDescription {
        switch source {
        case .allExceptCalls:
            return CATapDescription(stereoGlobalTapButExcludeProcesses: excludedIDs)
        case .process(let bundleID, _):
            let processIDs = try AudioSystem.audioProcesses()
                .filter { $0.bundleID == bundleID }
                .map(\.id)
            guard !processIDs.isEmpty else {
                throw SystemAudioTapStreamerError(message: "The selected capture app is not currently playing audio.")
            }
            return CATapDescription(stereoMixdownOfProcesses: processIDs)
        }
    }

    private func excludedProcessIDs() throws -> [AudioObjectID] {
        var excluded = Set<AudioObjectID>()
        if let ownProcess = try AudioSystem.processObjectID(pid: ProcessInfo.processInfo.processIdentifier) {
            excluded.insert(ownProcess)
        }
        for process in try AudioSystem.audioProcesses() where Self.callBundleIDs.contains(process.bundleID) {
            excluded.insert(process.id)
        }
        return Array(excluded)
    }

    private func createAggregate(outputDevice: AudioDevice, tapUID: String) throws -> AudioObjectID {
        let description: [String: Any] = [
            "name": AudioSystem.systemTapAggregateName,
            "uid": "\(AudioSystem.systemTapAggregateUID).\(UUID().uuidString)",
            "master": outputDevice.uid,
            "clock": outputDevice.uid,
            "private": true,
            "stacked": false,
            "tapautostart": true,
            "subdevices": [["uid": outputDevice.uid]],
            "taps": [["uid": tapUID, "drift": true]]
        ]

        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        try AudioSystem.check(
            AudioHardwareCreateAggregateDevice(description as CFDictionary, &newAggregateID),
            "create system tap aggregate"
        )
        return newAggregateID
    }

    private func startLoopback(aggregateID: AudioObjectID) throws {
        var newIOProcID: AudioDeviceIOProcID?
        try AudioSystem.check(
            AudioDeviceCreateIOProcIDWithBlock(&newIOProcID, aggregateID, queue) { _, inputData, _, outputData, _ in
                Self.copy(inputData: inputData, outputData: outputData)
            },
            "create system tap loopback"
        )

        guard let newIOProcID else {
            throw SystemAudioTapStreamerError(message: "CoreAudio did not create a system tap loopback.")
        }

        do {
            try AudioSystem.check(AudioDeviceStart(aggregateID, newIOProcID), "start system tap loopback")
            ioProcID = newIOProcID
        } catch {
            AudioDeviceDestroyIOProcID(aggregateID, newIOProcID)
            throw error
        }
    }

    private static func copy(
        inputData: UnsafePointer<AudioBufferList>,
        outputData: UnsafeMutablePointer<AudioBufferList>
    ) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        let outputs = UnsafeMutableAudioBufferListPointer(outputData)
        for output in outputs {
            if let data = output.mData {
                memset(data, 0, Int(output.mDataByteSize))
            }
        }

        for index in 0..<min(inputs.count, outputs.count) {
            let input = inputs[index]
            let output = outputs[index]
            guard let inputData = input.mData, let outputData = output.mData else { continue }
            memcpy(outputData, inputData, min(Int(input.mDataByteSize), Int(output.mDataByteSize)))
        }
    }
}
