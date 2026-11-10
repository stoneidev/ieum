// Experiment: can one SpeechAnalyzer run two SpeechTranscribers on the same audio, one with fast results (for the
// words on screen) and one without (for the finished sentences)? Fast results were measured to drop the tail of a
// Korean sentence with English words; the slow transcriber kept it. Plays the file in real time like caption-bench.
// Build: swiftc -O -parse-as-library -o /tmp/ieum-dual Benchmarks/research/dual.swift
// Run:   /tmp/ieum-dual <locale> <file.wav> [single|two]   ("single" = only the fast transcriber; "two" = a second,
//        separate analyzer for the slow transcriber instead of both modules in one analyzer)
import AVFoundation
import CoreMedia
import Foundation
import Speech

@main
struct Dual {
    static func main() async throws {
        let args = CommandLine.arguments
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: args[1]))!
        let url = URL(fileURLWithPath: args[2])
        let single = args.count > 3 && args[3] == "single"
        let two = args.count > 3 && args[3] == "two"
        let fast = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults],
                                     attributeOptions: [.audioTimeRange])
        let slow = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults],
                                     attributeOptions: [.audioTimeRange])
        let modules: [any SpeechModule] = single || two ? [fast] : [fast, slow]
        if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) { try await request.downloadAndInstall() }
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules)!
        let analyzer = SpeechAnalyzer(modules: modules)
        try await analyzer.prepareToAnalyze(in: format)
        let (input, cont) = AsyncStream.makeStream(of: AnalyzerInput.self)
        try await analyzer.start(inputSequence: input)
        var second: (SpeechAnalyzer, AsyncStream<AnalyzerInput>.Continuation)?
        if two {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [slow]) { try await request.downloadAndInstall() }
            let other = SpeechAnalyzer(modules: [slow])
            try await other.prepareToAnalyze(in: format)
            let (input2, cont2) = AsyncStream.makeStream(of: AnalyzerInput.self)
            try await other.start(inputSequence: input2)
            second = (other, cont2)
        }
        let zero = Date()
        func report(_ name: String, _ t: SpeechTranscriber) -> Task<Void, Never> {
            Task {
                do {
                    for try await r in t.results {
                        let text = String(r.text.characters)
                        let range = String(format: "%.1f-%.1f", r.range.start.seconds, r.range.end.seconds)
                        print(String(format: "%6.2fs %@ %@ %@ | %@", Date().timeIntervalSince(zero), name, r.isFinal ? "FINAL " : "interim", range, text))
                    }
                } catch { print("\(name) error: \(error)") }
            }
        }
        let a = report("fast", fast)
        let b = single ? nil : report("slow", slow)

        let file = try AVAudioFile(forReading: url)
        let converter = AVAudioConverter(from: file.processingFormat, to: format)!
        let chunk = AVAudioFrameCount(file.processingFormat.sampleRate / 10)
        var sent = 0.0
        func feed(_ buffer: AVAudioPCMBuffer) {
            let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 32)!
            var given = false
            var err: NSError?
            converter.convert(to: out, error: &err) { _, status in
                if given { status.pointee = .noDataNow; return nil }
                given = true; status.pointee = .haveData; return buffer
            }
            cont.yield(AnalyzerInput(buffer: out))
            second?.1.yield(AnalyzerInput(buffer: out))
        }
        while file.framePosition < file.length {
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk)!
            try file.read(into: buffer, frameCount: chunk)
            feed(buffer)
            sent += Double(buffer.frameLength) / file.processingFormat.sampleRate
            let wait = sent - Date().timeIntervalSince(zero)
            if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
        }
        // 2.5 s of silence, like caption-bench's tail.
        for _ in 0..<25 {
            let silence = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk)!
            silence.frameLength = chunk
            feed(silence)
            try await Task.sleep(for: .milliseconds(100))
        }
        cont.finish()
        second?.1.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        try await second?.0.finalizeAndFinishThroughEndOfInput()
        _ = await a.value
        _ = await b?.value
    }
}
