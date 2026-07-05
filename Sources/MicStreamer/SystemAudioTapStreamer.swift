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
    private let volumeLock = NSLock()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var volume: Float = 1

    var isRunning: Bool {
        ioProcID != nil
    }

    func start(
        outputDeviceID: AudioDeviceID,
        source: CaptureSource,
        volume: Float
    ) throws {
        stop()

        let outputDevice = try AudioSystem.device(id: outputDeviceID)
        let description = try tapDescription(for: source, excludedIDs: excludedProcessIDs())
        description.name = "MicStreamer System Audio"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        try AudioSystem.check(AudioHardwareCreateProcessTap(description, &newTapID), "create system audio tap")
        tapID = newTapID

        do {
            setVolume(volume)
            let tapUID = try AudioSystem.tapUID(newTapID)
            aggregateID = try createAggregate(outputDevice: outputDevice, tapUID: tapUID)
            try startLoopback(aggregateID: aggregateID)
        } catch {
            stop()
            throw error
        }
    }

    func setVolume(_ volume: Float) {
        volumeLock.lock()
        self.volume = AudioVolume.clamped(volume)
        volumeLock.unlock()
    }

    private func currentVolume() -> Float {
        volumeLock.lock()
        defer { volumeLock.unlock() }
        return volume
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
                throw MessageError("The selected capture app is not currently playing audio.")
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
        let sampleFormat = (try? Self.sampleFormat(deviceID: aggregateID)) ?? .passthrough
        try AudioSystem.check(
            AudioDeviceCreateIOProcIDWithBlock(
                &newIOProcID,
                aggregateID,
                queue
            ) { [weak self] _, inputData, _, outputData, _ in
                Self.copy(
                    inputData: inputData,
                    outputData: outputData,
                    volume: self?.currentVolume() ?? 1,
                    sampleFormat: sampleFormat
                )
            },
            "create system tap loopback"
        )

        guard let newIOProcID else {
            throw MessageError("CoreAudio did not create a system tap loopback.")
        }

        do {
            try AudioSystem.check(AudioDeviceStart(aggregateID, newIOProcID), "start system tap loopback")
            ioProcID = newIOProcID
        } catch {
            AudioDeviceDestroyIOProcID(aggregateID, newIOProcID)
            throw error
        }
    }

    private enum SampleFormat {
        case float32
        case int16
        case int32
        case passthrough
    }

    private static func sampleFormat(deviceID: AudioDeviceID) throws -> SampleFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)
        try AudioSystem.check(
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &format),
            "read system tap stream format"
        )

        guard format.mFormatID == kAudioFormatLinearPCM else { return .passthrough }
        if format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 {
            return .float32
        }
        if format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0 {
            if format.mBitsPerChannel == 16 { return .int16 }
            if format.mBitsPerChannel == 32 { return .int32 }
        }
        return .passthrough
    }

    private static func copy(
        inputData: UnsafePointer<AudioBufferList>,
        outputData: UnsafeMutablePointer<AudioBufferList>,
        volume: Float,
        sampleFormat: SampleFormat
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
            let byteCount = min(Int(input.mDataByteSize), Int(output.mDataByteSize))
            if volume == 1 || sampleFormat == .passthrough {
                memcpy(outputData, inputData, byteCount)
            } else {
                copy(
                    inputData: inputData,
                    outputData: outputData,
                    byteCount: byteCount,
                    volume: volume,
                    as: sampleFormat
                )
            }
        }
    }

    private static func copy(
        inputData: UnsafeMutableRawPointer,
        outputData: UnsafeMutableRawPointer,
        byteCount: Int,
        volume: Float,
        as sampleFormat: SampleFormat
    ) {
        switch sampleFormat {
        case .float32:
            let count = byteCount / MemoryLayout<Float>.stride
            let input = inputData.bindMemory(to: Float.self, capacity: count)
            let output = outputData.bindMemory(to: Float.self, capacity: count)
            for index in 0..<count {
                output[index] = input[index] * volume
            }
        case .int16:
            let count = byteCount / MemoryLayout<Int16>.stride
            let input = inputData.bindMemory(to: Int16.self, capacity: count)
            let output = outputData.bindMemory(to: Int16.self, capacity: count)
            for index in 0..<count {
                output[index] = AudioVolume.scale(input[index], by: volume)
            }
        case .int32:
            let count = byteCount / MemoryLayout<Int32>.stride
            let input = inputData.bindMemory(to: Int32.self, capacity: count)
            let output = outputData.bindMemory(to: Int32.self, capacity: count)
            for index in 0..<count {
                output[index] = AudioVolume.scale(input[index], by: volume)
            }
        case .passthrough:
            memcpy(outputData, inputData, byteCount)
        }
    }
}
