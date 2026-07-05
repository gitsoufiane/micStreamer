import AVFoundation
import AudioToolbox
import CoreAudio

struct MicrophoneMixerError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

@MainActor
final class MicrophoneMixer {
    private let engine = AVAudioEngine()

    var volume: Float = 1 {
        didSet {
            engine.mainMixerNode.outputVolume = volume
        }
    }

    var isRunning: Bool {
        engine.isRunning
    }

    func start(inputDeviceID: AudioDeviceID, outputDeviceID: AudioDeviceID, volume: Float) throws {
        stop()
        try setDevice(inputDeviceID, on: engine.inputNode.audioUnit, action: "set microphone input")
        try setDevice(outputDeviceID, on: engine.outputNode.audioUnit, action: "set BlackHole output")
        self.volume = AudioVolume.clamped(volume)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else {
            throw MicrophoneMixerError(message: "The selected microphone has no input channels.")
        }

        engine.connect(input, to: engine.mainMixerNode, format: inputFormat)
        engine.prepare()
        try engine.start()
    }

    func stop() {
        if engine.isRunning {
            engine.stop()
        }
        engine.disconnectNodeOutput(engine.inputNode)
        engine.reset()
    }

    private func setDevice(_ id: AudioDeviceID, on unit: AudioUnit?, action: String) throws {
        guard let unit else {
            throw MicrophoneMixerError(message: "CoreAudio failed to \(action): missing audio unit.")
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
            throw MicrophoneMixerError(message: "CoreAudio failed to \(action). OSStatus: \(status).")
        }
    }
}
