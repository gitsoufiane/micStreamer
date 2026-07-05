import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

struct BlackHoleSelfTestError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

final class BlackHoleSelfTest {
    func run() async throws -> String {
        let blackHole = try AudioSystem.blackHoleOutputDevice()
        let inputEngine = AVAudioEngine()
        let outputEngine = AVAudioEngine()
        let meter = PeakMeter()

        try setDevice(blackHole.id, on: inputEngine.inputNode.audioUnit, action: "set BlackHole test input")
        try setDevice(blackHole.id, on: outputEngine.outputNode.audioUnit, action: "set BlackHole test output")

        let input = inputEngine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            meter.measure(buffer)
        }

        let toneFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let tone = ToneSource(format: toneFormat)
        outputEngine.attach(tone.node)
        outputEngine.connect(tone.node, to: outputEngine.mainMixerNode, format: toneFormat)

        do {
            try inputEngine.start()
            try outputEngine.start()
            try await Task.sleep(nanoseconds: 1_200_000_000)
        } catch {
            input.removeTap(onBus: 0)
            inputEngine.stop()
            outputEngine.stop()
            throw error
        }

        input.removeTap(onBus: 0)
        inputEngine.stop()
        outputEngine.stop()

        guard meter.peak > 0.01 else {
            throw BlackHoleSelfTestError(message: "BlackHole self-test did not detect the test tone.")
        }
        return "BlackHole self-test passed. Test tone was detected."
    }

    private func setDevice(_ id: AudioDeviceID, on unit: AudioUnit?, action: String) throws {
        guard let unit else {
            throw BlackHoleSelfTestError(message: "CoreAudio failed to \(action): missing audio unit.")
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
            throw BlackHoleSelfTestError(message: "CoreAudio failed to \(action). OSStatus: \(status).")
        }
    }
}

private final class PeakMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var measuredPeak: Float = 0

    var peak: Float {
        lock.withLock { measuredPeak }
    }

    func measure(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        var localPeak: Float = 0
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameCount {
                localPeak = max(localPeak, abs(samples[frame]))
            }
        }
        lock.withLock {
            measuredPeak = max(measuredPeak, localPeak)
        }
    }
}

private final class ToneSource {
    let node: AVAudioSourceNode

    init(format: AVAudioFormat) {
        let state = ToneState(sampleRate: format.sampleRate)
        let channels = Int(format.channelCount)
        node = AVAudioSourceNode { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let sample = state.nextSample()
                for channel in 0..<min(channels, buffers.count) {
                    let buffer = buffers[channel]
                    if let data = buffer.mData?.assumingMemoryBound(to: Float.self) {
                        data[frame] = sample
                    }
                }
            }
            return noErr
        }
    }
}

private final class ToneState: @unchecked Sendable {
    private let sampleRate: Double
    private var phase = 0.0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    func nextSample() -> Float {
        let sample = Float(sin(phase) * 0.2)
        phase += 2.0 * Double.pi * 440.0 / sampleRate
        if phase > 2.0 * Double.pi {
            phase -= 2.0 * Double.pi
        }
        return sample
    }
}
