import AppKit
import CaptionCore
import CryptoKit
import Foundation
import Security

/// Looks for a newer Ieum and, when the person says yes, installs it.
///
/// The only network request Ieum makes of its own is the feed (`latest.json`, a few hundred bytes) and, after a yes, the
/// download of the disk image. Nothing is sent but the request itself. An update is installed only after it matches the
/// published SHA-256, is signed by the same developer team as the running app and passes Gatekeeper's notarization check.
@MainActor
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateFeed)
        case needsNewerMacOS(String)
        case downloading(Double)
        case verifying
        case installing
        /// The app could not be replaced in place (for example it is not in a writable folder): the verified copy is ready.
        case manualInstall(URL)
        case failed(String)
    }

    static let defaultFeed = URL(string: "https://ieum.calmwork.today/latest.json")!
    static let releasePage = URL(string: "https://github.com/stoneidev/ieum/releases/latest")!

    @Published private(set) var state: State = .idle
    @Published private(set) var lastCheck: Date? = Preferences.lastUpdateCheck
    /// Set by the app delegate: shows the update window.
    var present: () -> Void = {}
    /// Set by the app delegate: true while captions run. An automatic check never interrupts a meeting; it waits for the next round.
    var isBusy: () -> Bool = { false }

    private var timer: Timer?
    private var work: Task<Void, Never>?

    private var currentVersion: String {
        Preferences.updateCurrentVersionOverride ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    private var feedURL: URL { Preferences.updateFeedOverride ?? Self.defaultFeed }

    // MARK: Schedule

    /// Starts the automatic checks: shortly after launch, then every few hours, each only when a day has passed.
    func start() {
        guard Preferences.autoCheckUpdates else { return }
        Task { try? await Task.sleep(for: .seconds(8)); checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
    }

    private func checkIfDue() {
        guard Preferences.autoCheckUpdates, !isBusy(), state == .idle || state == .upToDate,
              UpdateCheck.isDue(lastCheck: Preferences.lastUpdateCheck, now: Date())
        else { return }
        check(userInitiated: false)
    }

    // MARK: Check

    /// "Check for updates…": always answers, in the update window.
    func checkNow() {
        present()
        check(userInitiated: true)
    }

    private func check(userInitiated: Bool) {
        guard work == nil else { return }
        if userInitiated { state = .checking }
        work = Task { [weak self] in
            await self?.performCheck(userInitiated: userInitiated)
            self?.work = nil
        }
    }

    private func performCheck(userInitiated: Bool) async {
        do {
            var request = URLRequest(url: feedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            request.setValue("Ieum/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.feed }
            let feed = try JSONDecoder().decode(UpdateFeed.self, from: data)
            Preferences.lastUpdateCheck = Date()
            lastCheck = Preferences.lastUpdateCheck
            let system = ProcessInfo.processInfo.operatingSystemVersion
            let outcome = UpdateCheck.evaluate(
                feed: feed, current: currentVersion, skipped: Preferences.skippedUpdateVersion,
                macOS: "\(system.majorVersion).\(system.minorVersion)", userInitiated: userInitiated,
                allowLocalHost: Preferences.updateFeedOverride != nil
            )
            switch outcome {
            case .available(let offered):
                state = .available(offered)
                present()
            case .upToDate, .skipped:
                state = userInitiated ? .upToDate : .idle
            case .needsNewerMacOS(_, let required):
                state = userInitiated ? .needsNewerMacOS(required) : .idle
            case .invalid:
                throw UpdateError.feed
            }
        } catch {
            // An automatic check that cannot reach the website says nothing; only a check the person asked for does.
            state = userInitiated ? .failed(Self.describe(error)) : .idle
        }
    }

    // MARK: Answers

    func skip(_ feed: UpdateFeed) {
        Preferences.skippedUpdateVersion = feed.version
        state = .idle
    }

    func dismiss() {
        if case .available = state { state = .idle }
        if case .failed = state { state = .idle }
        if state == .upToDate { state = .idle }
    }

    // MARK: Install

    func install(_ feed: UpdateFeed) {
        guard work == nil else { return }
        work = Task { [weak self] in
            await self?.performInstall(feed)
            self?.work = nil
        }
    }

    private func performInstall(_ feed: UpdateFeed) async {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ieum-update-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            state = .downloading(0)
            let image = folder.appendingPathComponent("Ieum.dmg")
            try await download(feed, to: image)
            state = .verifying
            let staged = try await stage(image, in: folder, expecting: feed.version)
            try await replaceAndRelaunch(with: staged, folder: folder)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            state = .failed(Self.describe(error))
        }
    }

    private func download(_ feed: UpdateFeed, to file: URL) async throws {
        let allowLocal = Preferences.updateFeedOverride != nil
        guard UpdateCheck.isValidDownload(feed.url, allowLocalHost: allowLocal) else { throw UpdateError.feed }
        var request = URLRequest(url: feed.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("Ieum/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let expected = Double(feed.size ?? 0)
        let downloaded = try await Downloader.fetch(request) { [weak self] written, total in
            let whole = total > 0 ? Double(total) : expected
            if whole > 0 { Task { @MainActor in self?.state = .downloading(min(1, Double(written) / whole)) } }
        }
        try FileManager.default.moveItem(at: downloaded, to: file)
        // Read back in pieces and compare with what was published.
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == feed.sha256 else { throw UpdateError.checksum }
    }

    /// Opens the disk image, copies the app out, and refuses it unless it is the version promised, signed by our team and notarized.
    private func stage(_ image: URL, in folder: URL, expecting version: String) async throws -> URL {
        let mount = folder.appendingPathComponent("mount")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        guard try await Self.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, image.path]).status == 0
        else { throw UpdateError.image }
        let source = mount.appendingPathComponent("Ieum.app")
        let staged = folder.appendingPathComponent("stage/Ieum.app")
        try FileManager.default.createDirectory(at: staged.deletingLastPathComponent(), withIntermediateDirectories: true)
        let copied = try? await Self.run("/usr/bin/ditto", [source.path, staged.path])
        // The image is not needed any more; close it before anything else can go wrong.
        _ = try? await Self.run("/usr/bin/hdiutil", ["detach", "-force", mount.path])
        guard copied?.status == 0 else { throw UpdateError.image }

        guard let ours = Self.teamIdentifier(of: Bundle.main.bundleURL), let theirs = Self.teamIdentifier(of: staged), ours == theirs
        else { throw UpdateError.signature }
        guard try await Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path]).status == 0 else { throw UpdateError.signature }
        guard try await Self.run("/usr/sbin/spctl", ["--assess", "--type", "execute", staged.path]).status == 0 else { throw UpdateError.notarization }
        let info = NSDictionary(contentsOf: staged.appendingPathComponent("Contents/Info.plist"))
        guard (info?["CFBundleShortVersionString"] as? String) == version else { throw UpdateError.image }
        return staged
    }

    private func replaceAndRelaunch(with staged: URL, folder: URL) async throws {
        let target = Bundle.main.bundleURL
        let parent = target.deletingLastPathComponent().path
        guard FileManager.default.isWritableFile(atPath: parent), !target.path.contains("/.build/") else {
            // Cannot replace this copy (a read-only location, or a development build): leave the verified app where it can be found.
            let kept = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!.appendingPathComponent("Ieum.app")
            try? FileManager.default.removeItem(at: kept)
            try FileManager.default.moveItem(at: staged, to: kept)
            try? FileManager.default.removeItem(at: folder)
            state = .manualInstall(kept)
            return
        }
        // A short script does the swap after this process has quit: the old app is moved aside first, and put back if anything fails.
        let script = folder.appendingPathComponent("swap.sh")
        try """
        #!/bin/sh
        PID="$1"; NEW="$2"; OLD="$3"; WORK="$4"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
        BACKUP="$OLD.previous"
        rm -rf "$BACKUP"
        mv "$OLD" "$BACKUP" || { open "$OLD"; exit 1; }
        if ditto "$NEW" "$OLD"; then
          rm -rf "$BACKUP"
          xattr -dr com.apple.quarantine "$OLD" 2>/dev/null
        else
          rm -rf "$OLD"; mv "$BACKUP" "$OLD"
        fi
        open "$OLD"
        rm -rf "$WORK"
        """.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), staged.path, target.path, folder.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        state = .installing
        try? await Task.sleep(for: .milliseconds(600))
        NSApp.terminate(nil)
    }

    // MARK: Helpers

    private enum UpdateError: Error {
        case feed, download, checksum, image, signature, notarization
    }

    private static func describe(_ error: Error) -> String {
        switch error as? UpdateError {
        case .feed?: return tr("The update information could not be read.", "업데이트 정보를 읽을 수 없습니다.")
        case .download?: return tr("The download failed.", "내려받지 못했습니다.")
        case .checksum?: return tr("The download does not match what was published, so it was not installed.", "내려받은 파일이 공개된 것과 달라서 설치하지 않았습니다.")
        case .image?: return tr("The update package could not be opened.", "업데이트 파일을 열 수 없습니다.")
        case .signature?: return tr("The update is not signed by the same developer as this app, so it was not installed.", "업데이트가 이 앱과 같은 개발자의 서명이 아니어서 설치하지 않았습니다.")
        case .notarization?: return tr("macOS did not accept the update (notarization check failed), so it was not installed.", "macOS가 업데이트를 인정하지 않아(공증 확인 실패) 설치하지 않았습니다.")
        case nil:
            if (error as? URLError) != nil {
                return tr("Could not reach the update server. Check the internet connection.", "업데이트 서버에 연결하지 못했습니다. 인터넷 연결을 확인하세요.")
            }
            return error.localizedDescription
        }
    }

    /// The developer team that signed the app at `url`, or nil when it is not signed with a team (an ad-hoc development build).
    private static func teamIdentifier(of url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any]
        else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static func run(_ path: String, _ arguments: [String]) async throws -> (status: Int32, output: String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { finished in
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: (finished.terminationStatus, output))
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}

/// A file download with progress, on its own ephemeral session.
private final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Int64, Int64) -> Void
    private var continuation: CheckedContinuation<URL, Error>?

    private init(progress: @escaping @Sendable (Int64, Int64) -> Void) { self.progress = progress }

    static func fetch(_ request: URLRequest, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> URL {
        let downloader = Downloader(progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: downloader, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            downloader.continuation = continuation
            session.downloadTask(with: request).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else {
            resume(with: .failure(URLError(.badServerResponse)))
            return
        }
        // The system deletes `location` when this returns, so keep the file.
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("ieum-download-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            resume(with: .success(kept))
        } catch {
            resume(with: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { resume(with: .failure(error)) }
    }

    private func resume(with result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}
