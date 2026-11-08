import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Desktop audio capture through ScreenCaptureKit; no video output is attached.
public final class SystemAudioCapture: NSObject, AudioCapture, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var stream: SCStream?
    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private var failure: String?
    private let queue = DispatchQueue(label: "mac-stt.system-audio", qos: .userInteractive)

    public override init() { super.init() }

    /// Why the stream ended on its own (for example the display went to sleep), nil after a normal stop.
    public var failureMessage: String? { lock.withLock { failure } }

    public func start() async throws -> AsyncStream<AudioChunk> {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw EngineError.permissionDenied(
                "System audio is blocked (\(error.localizedDescription)). Allow this app under "
                    + "System Settings > Privacy & Security > Screen & System Audio Recording, then start again."
            )
        }
        guard let display = content.displays.first else {
            throw EngineError.captureFailed("No display found; ScreenCaptureKit needs one to capture system audio.")
        }

        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 1
        // Video is never consumed; keep the unavoidable frame stream as small and slow as possible.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.showsCursor = false

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)

        let (audio, continuation) = AsyncStream.makeStream(of: AudioChunk.self, bufferingPolicy: .unbounded)
        lock.withLock {
            self.stream = stream
            self.continuation = continuation
        }
        do {
            try await stream.startCapture()
        } catch {
            lock.withLock {
                self.stream = nil
                self.continuation = nil
            }
            continuation.finish()
            throw EngineError.captureFailed("Could not start system audio capture: \(error.localizedDescription)")
        }
        return audio
    }

    public func stop() async {
        let (stream, continuation) = lock.withLock { () -> (SCStream?, AsyncStream<AudioChunk>.Continuation?) in
            defer {
                self.stream = nil
                self.continuation = nil
            }
            return (self.stream, self.continuation)
        }
        if let stream { try? await stream.stopCapture() }
        continuation?.finish()
    }

    // MARK: SCStreamOutput

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, let buffer = Self.pcmBuffer(from: sampleBuffer) else { return }
        let continuation = lock.withLock { self.continuation }
        continuation?.yield(AudioChunk(buffer: buffer))
    }

    // MARK: SCStreamDelegate

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.withLock { failure = error.localizedDescription }
        FileHandle.standardError.write(Data("mac-stt: system audio stream stopped: \(error.localizedDescription)\n".utf8))
        let continuation = lock.withLock { () -> AsyncStream<AudioChunk>.Continuation? in
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.finish()
    }

    // MARK: Conversion

    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = sampleBuffer.formatDescription,
              let asbd = description.audioStreamBasicDescription
        else { return nil }
        var streamDescription = asbd
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        pcm.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frames),
            into: pcm.mutableAudioBufferList
        )
        return status == noErr ? pcm : nil
    }
}
