import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

enum AudioLevel {
    static let floorDB: Float = -160

    /// RMS level of the first channel in dBFS, floored at `floorDB`.
    static func rmsDB(of buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return floorDB }
        var sumSquares: Double = 0
        if let channels = buffer.floatChannelData {
            let samples = channels[0]
            for i in 0..<frames { sumSquares += Double(samples[i] * samples[i]) }
        } else if let channels = buffer.int16ChannelData {
            let samples = channels[0]
            for i in 0..<frames {
                let v = Double(samples[i]) / Double(Int16.max)
                sumSquares += v * v
            }
        } else {
            return floorDB
        }
        let rms = (sumSquares / Double(frames)).squareRoot()
        guard rms > 0 else { return floorDB }
        return max(floorDB, Float(20 * log10(rms)))
    }
}

extension AVAudioPCMBuffer {
    /// Deep copy, so the buffer can safely outlive the audio tap callback.
    func copied() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }
        copy.frameLength = frameLength
        let source = UnsafeMutableAudioBufferListPointer(mutableAudioBufferList)
        let target = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (src, dst) in zip(source, target) {
            guard let from = src.mData, let to = dst.mData else { continue }
            memcpy(to, from, Int(min(src.mDataByteSize, dst.mDataByteSize)))
        }
        return copy
    }
}

extension AVAudioPCMBuffer {
    /// Mono float copy taken from the loudest channel.
    /// Voice-processed input arrives as a many-channel stream (9 on Apple Silicon) where the clean voice is not
    /// guaranteed to be channel 0, and averaging would dilute it with silent reference channels.
    func loudestChannelMono() -> AVAudioPCMBuffer? {
        guard let channels = floatChannelData,
              let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate, channels: 1, interleaved: false),
              let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: frameLength)
        else { return nil }
        let frames = Int(frameLength)
        var best = 0
        var bestEnergy: Float = -1
        for channel in 0..<Int(format.channelCount) {
            var energy: Float = 0
            for i in 0..<frames { energy += channels[channel][i] * channels[channel][i] }
            if energy > bestEnergy { bestEnergy = energy; best = channel }
        }
        mono.frameLength = frameLength
        memcpy(mono.floatChannelData![0], channels[best], frames * MemoryLayout<Float>.size)
        return mono
    }
}

extension AudioChunk {
    init(buffer: AVAudioPCMBuffer) {
        let rate = buffer.format.sampleRate
        self.init(
            buffer: buffer,
            levelDB: AudioLevel.rmsDB(of: buffer),
            duration: rate > 0 ? Double(buffer.frameLength) / rate : 0
        )
    }
}

/// Tracks how long the input has been below the silence threshold.
struct SilenceDetector {
    static let defaultThresholdDB: Float = -50

    let thresholdDB: Float
    private(set) var silentDuration: TimeInterval = 0
    private(set) var hasHeardSpeech = false

    init(thresholdDB: Float = SilenceDetector.defaultThresholdDB) {
        self.thresholdDB = thresholdDB
    }

    mutating func ingest(levelDB: Float, duration: TimeInterval) {
        if levelDB < thresholdDB {
            silentDuration += duration
        } else {
            silentDuration = 0
            hasHeardSpeech = true
        }
    }

    mutating func reset() {
        silentDuration = 0
        hasHeardSpeech = false
    }
}

/// Live microphone capture through `AVAudioEngine.inputNode`.
public final class MicrophoneCapture: AudioCapture, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let voiceProcessing: Bool
    private let deviceUID: String?
    private let lock = NSLock()
    private var continuation: AsyncStream<AudioChunk>.Continuation?

    /// - Parameters:
    ///   - voiceProcessing: enable the system's noise suppression / AGC / echo cancellation on the input.
    ///   - deviceUID: CoreAudio UID of the input device to use; nil means the system default input.
    public init(voiceProcessing: Bool = false, deviceUID: String? = nil) {
        self.voiceProcessing = voiceProcessing
        self.deviceUID = deviceUID
    }

    /// Resolves a CoreAudio device UID (e.g. from an input picker) to its device ID.
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var cfUID = uid as CFString
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { qualifier in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<CFString>.size), qualifier, &size, &deviceID
            )
        }
        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
    }

    private func selectDevice(on input: AVAudioInputNode) throws {
        guard let deviceUID else { return }
        guard var device = Self.deviceID(forUID: deviceUID), let unit = input.audioUnit else {
            throw EngineError.captureFailed("Input device '\(deviceUID)' was not found.")
        }
        let status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
            &device, UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw EngineError.captureFailed("Could not select input device '\(deviceUID)' (error \(status)).")
        }
    }

    public func start() async throws -> AsyncStream<AudioChunk> {
        guard await AVAudioApplication.requestRecordPermission() else {
            throw EngineError.permissionDenied(
                "Microphone access is blocked. Allow this app under System Settings > Privacy & Security > Microphone, then start again."
            )
        }
        let input = engine.inputNode
        try selectDevice(on: input)
        if voiceProcessing {
            // Must happen before the node format is read: enabling it can change rate and channel count.
            do {
                try input.setVoiceProcessingEnabled(true)
                input.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
            } catch {
                throw EngineError.captureFailed("Could not enable voice processing: \(error.localizedDescription)")
            }
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw EngineError.captureFailed("No usable microphone input device was found.")
        }

        let (stream, continuation) = AsyncStream.makeStream(of: AudioChunk.self, bufferingPolicy: .unbounded)
        lock.withLock { self.continuation = continuation }

        let mixDown = voiceProcessing
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            let copy = mixDown && buffer.format.channelCount > 1 ? buffer.loudestChannelMono() : buffer.copied()
            guard let copy else { return }
            continuation.yield(AudioChunk(buffer: copy))
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            continuation.finish()
            throw EngineError.captureFailed("Could not start the audio engine: \(error.localizedDescription)")
        }
        return stream
    }

    public func stop() async {
        let continuation = lock.withLock { () -> AsyncStream<AudioChunk>.Continuation? in
            defer { self.continuation = nil }
            return self.continuation
        }
        guard let continuation else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation.finish()
    }
}
