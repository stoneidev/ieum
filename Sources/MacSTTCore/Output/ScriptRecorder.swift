import Foundation

/// Appends finalized sentences to a per-session text file, one `[HH:mm:ss] text` line each.
/// Every write goes straight to the file, so a crash loses at most the sentence in progress.
public final class ScriptRecorder: @unchecked Sendable {
    public let fileURL: URL
    private let lock = NSLock()
    private let handle: FileHandle
    private let timeZone: TimeZone
    private var closed = false

    /// Creates a new file in `directory`; an existing file is never reused or overwritten.
    public init(directory: URL, locale: String, startedAt: Date = Date(), timeZone: TimeZone = .current) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.timeZone = timeZone

        let stamp = Self.format(startedAt, "yyyy-MM-dd_HHmmss", timeZone)
        let base = "transcript-\(stamp)-\(locale)"
        var url = directory.appendingPathComponent(base + ".txt")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(base)-\(suffix).txt")
            suffix += 1
        }
        let header = "# Transcript (\(locale)) started \(Self.format(startedAt, "yyyy-MM-dd HH:mm:ss", timeZone))\n"
        guard FileManager.default.createFile(atPath: url.path, contents: Data(header.utf8)) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        fileURL = url
    }

    /// Records finalized, non-empty events only.
    public func append(_ event: TranscriptionEvent) {
        guard event.isFinal else { return }
        let text = RepetitionGuard.collapse(event.text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !text.isEmpty else { return }
        let line = "[\(Self.format(event.timestamp, "HH:mm:ss", timeZone))] \(text)\n"
        lock.withLock {
            guard !closed else { return }
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }

    /// Adds the translation of an earlier sentence as `[HH:mm:ss] → translation`, using the sentence's own timestamp
    /// so the pair can be matched even when another sentence was written in between.
    public func appendTranslation(_ translation: String, forSentenceAt time: Date) {
        let text = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let line = "[\(Self.format(time, "HH:mm:ss", timeZone))] → \(text)\n"
        lock.withLock {
            guard !closed else { return }
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }

    public func close() {
        lock.withLock {
            guard !closed else { return }
            closed = true
            try? handle.close()
        }
    }

    deinit { close() }

    private static func format(_ date: Date, _ pattern: String, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
