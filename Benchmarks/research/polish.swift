// Runs recognized sentences (one per line) through Apple's on-device language model with the same instructions as
// CaptionCore's FinalTextPolisher, and prints "<seconds>\t<output>" per line. Used to measure whether the polish step
// helps punctuation, spacing and numbers before it is wired into the app.
// Usage: swiftc -O -o /tmp/ieum-polish Benchmarks/research/polish.swift && /tmp/ieum-polish Benchmarks/research/polish-input.txt
import Foundation
import FoundationModels

let instructions = """
You fix speech-recognition errors: spacing, punctuation, and clearly misheard words. \
Keep the speaker's language, wording and meaning. Never translate, answer, summarize, reorder, add or remove content. \
Output only the corrected sentence.
"""

let model = SystemLanguageModel.default
guard case .available = model.availability else {
    print("unavailable: \(model.availability)")
    exit(1)
}
let lines = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
    .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
// Load the model once before timing.
_ = try? await LanguageModelSession(instructions: instructions).respond(to: "준비")
for line in lines {
    let start = Date()
    let session = LanguageModelSession(instructions: instructions)
    let out = (try? await session.respond(to: line, options: GenerationOptions(temperature: 0)).content) ?? "<error>"
    print(String(format: "%.2f", Date().timeIntervalSince(start)) + "\t" + out.replacingOccurrences(of: "\n", with: " "))
}
