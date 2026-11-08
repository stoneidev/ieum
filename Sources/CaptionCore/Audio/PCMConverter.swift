import AVFoundation

/// Converts capture buffers to the format an engine asked for. Not thread-safe; own it from one task.
final class PCMConverter {
    private let converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat

    init?(from input: AVAudioFormat, to output: AVAudioFormat) {
        outputFormat = output
        if input == output {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: input, to: output) else { return nil }
            self.converter = converter
        }
    }

    func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return input }
        let ratio = outputFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }

        final class Feed: @unchecked Sendable { var consumed = false }
        let feed = Feed()
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if feed.consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            feed.consumed = true
            outStatus.pointee = .haveData
            return input
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}
