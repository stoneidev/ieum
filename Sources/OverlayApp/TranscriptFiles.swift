import Foundation
import CaptionCore

/// File operations on saved transcripts.
enum TranscriptFiles {
    /// Gives the transcript at `url` the name `title`; its exported subtitle and notes files beside it follow.
    /// Returns the new location, or nil when the name would not change. If one move fails, the ones already made are undone.
    @discardableResult
    static func rename(_ url: URL, to title: String) throws -> URL? {
        let directory = url.deletingLastPathComponent()
        let existing = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        guard let plan = TranscriptNaming.renamePlan(oldBase: url.deletingPathExtension().lastPathComponent, title: title, existing: existing) else { return nil }
        var done: [(from: URL, to: URL)] = []
        do {
            for move in plan.moves {
                let from = directory.appendingPathComponent(move.from), to = directory.appendingPathComponent(move.to)
                try FileManager.default.moveItem(at: from, to: to)
                done.append((from, to))
            }
        } catch {
            for moved in done.reversed() { try? FileManager.default.moveItem(at: moved.to, to: moved.from) }
            throw error
        }
        return directory.appendingPathComponent("\(plan.newBase).txt")
    }
}
