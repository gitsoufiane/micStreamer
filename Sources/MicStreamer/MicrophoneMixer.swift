import AVFoundation
import CoreAudio

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
        try AudioSystem.setCurrentDevice(
            inputDeviceID,
            on: engine.inputNode.audioUnit,
            action: "set microphone input"
        )
        try AudioSystem.setCurrentDevice(
            outputDeviceID,
            on: engine.outputNode.audioUnit,
            action: "set BlackHole output"
        )
        self.volume = AudioVolume.clamped(volume)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else {
            throw MessageError("The selected microphone has no input channels.")
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

}
