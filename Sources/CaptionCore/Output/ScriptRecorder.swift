import Foundation

/// Appends finalized sentences to a per-session text file, one `[HH:mm:ss] text` line each.
/// Every write goes straight to the file, so a crash loses at most the sentence in progress.
public final class ScriptRecorder: @unchecked Sendable {
    public let fileURL: URL
    private let lock = NSLock()
    private var handle: FileHandle?
    private let header: String
    private let timeZone: TimeZone
    private let tagLanguages: Bool
    private let tagSpeakers: Bool
    private var closed = false
    private var reportedFailure = false
    private var failureHandler: (@Sendable (String) -> Void)?

    /// Chooses a new file name in `directory` (an existing file is never reused or overwritten). The file itself is
    /// created when the first sentence is written, so a session that hears nothing leaves no empty file behind.
    /// - Parameters:
    ///   - tagLanguages: write `[EN]` / `[KO]` after the time, for conversations that switch language.
    ///   - tagSpeakers: write `[ME]` / `[THEM]` instead, for calls where the microphone and the other side are recognized apart.
    public init(directory: URL, locale: String, startedAt: Date = Date(), timeZone: TimeZone = .current, tagLanguages: Bool = false, tagSpeakers: Bool = false) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.timeZone = timeZone
        self.tagLanguages = tagLanguages
        self.tagSpeakers = tagSpeakers

        let stamp = Self.format(startedAt, "yyyy-MM-dd_HHmmss", timeZone)
        let base = "transcript-\(stamp)-\(locale)"
        var url = directory.appendingPathComponent(base + ".txt")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(base)-\(suffix).txt")
            suffix += 1
        }
        // Fail now, not at the first sentence, when the folder cannot be written to.
        guard FileManager.default.isWritableFile(atPath: directory.path) else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: directory.path])
        }
        header = "# Transcript (\(locale)) started \(Self.format(startedAt, "yyyy-MM-dd HH:mm:ss", timeZone))\n"
        fileURL = url
    }

    /// Called once, with a readable reason, if the transcript can no longer be written (disk full, folder removed).
    public func onFailure(_ handler: @escaping @Sendable (String) -> Void) {
        lock.withLock { failureHandler = handler }
    }

    /// Writes one line. Callers hold the lock.
    private func write(_ line: String) {
        do {
            guard let file = openIfNeeded() else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: fileURL.path]) }
            try file.write(contentsOf: Data(line.utf8))
        } catch {
            guard !reportedFailure else { return }
            reportedFailure = true
            failureHandler?(error.localizedDescription)
        }
    }

    /// Opens the file on first use. Callers hold the lock.
    private func openIfNeeded() -> FileHandle? {
        if let handle { return handle }
        guard FileManager.default.createFile(atPath: fileURL.path, contents: Data(header.utf8)),
              let opened = try? FileHandle(forWritingTo: fileURL) else { return nil }
        _ = try? opened.seekToEnd()
        handle = opened
        return opened
    }

    /// Records finalized, non-empty events only.
    public func append(_ event: TranscriptionEvent) {
        guard event.isFinal else { return }
        let text = RepetitionGuard.collapse(event.text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !text.isEmpty else { return }
        let line = "[\(Self.format(event.timestamp, "HH:mm:ss", timeZone))] \(tag(locale: event.locale, speaker: event.speaker))\(text)\n"
        lock.withLock {
            guard !closed else { return }
            write(line)
        }
    }

    /// Adds the translation of an earlier sentence as `[HH:mm:ss] → translation`, using the sentence's own timestamp
    /// so the pair can be matched even when another sentence was written in between.
    public func appendTranslation(_ translation: String, forSentenceAt time: Date, targetLanguage: String? = nil, speaker: Speaker? = nil) {
        let text = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let line = "[\(Self.format(time, "HH:mm:ss", timeZone))] \(tag(locale: targetLanguage, speaker: speaker))→ \(text)\n"
        lock.withLock {
            guard !closed else { return }
            write(line)
        }
    }

    public func close() {
        lock.withLock {
            guard !closed else { return }
            closed = true
            try? handle?.close()
        }
    }

    deinit { close() }

    private func tag(locale: String?, speaker: Speaker?) -> String {
        if tagSpeakers { return speaker.map { "[\($0.rawValue.uppercased())] " } ?? "" }
        return languageTag(locale)
    }

    private func languageTag(_ locale: String?) -> String {
        guard tagLanguages, let locale, locale.count >= 2 else { return "" }
        return "[\(locale.prefix(2).uppercased())] "
    }

    private static func format(_ date: Date, _ pattern: String, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
