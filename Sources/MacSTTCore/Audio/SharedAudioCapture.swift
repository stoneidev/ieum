import Foundation

/// One capture source feeding several consumers with the same audio at the same time.
///
/// Conversation mode runs two recognizers (one per language) on the same microphone. Each gets its own branch.
/// The source starts only once every branch has asked for audio, so that all branches see the very first chunk
/// and their timelines line up. It stops when every branch has stopped.
public final class SharedAudioCapture: @unchecked Sendable {
    private let source: any AudioCapture
    private let expected: Int
    private let lock = NSLock()
    private var continuations: [Int: AsyncStream<AudioChunk>.Continuation] = [:]
    private var waiters: [CheckedContinuation<Void, Error>] = []
    private var startResult: Result<Void, Error>?
    private var stoppedBranches = Set<Int>()
    private var pump: Task<Void, Never>?

    public private(set) var branches: [any AudioCapture] = []

    public init(source: any AudioCapture, branchCount: Int) {
        self.source = source
        expected = max(1, branchCount)
        branches = (0..<expected).map { Branch(owner: self, index: $0) }
    }

    private final class Branch: AudioCapture, @unchecked Sendable {
        let owner: SharedAudioCapture
        let index: Int
        init(owner: SharedAudioCapture, index: Int) {
            self.owner = owner
            self.index = index
        }
        func start() async throws -> AsyncStream<AudioChunk> { try await owner.startBranch(index) }
        func stop() async { await owner.stopBranch(index) }
    }

    private func startBranch(_ index: Int) async throws -> AsyncStream<AudioChunk> {
        let (stream, continuation) = AsyncStream.makeStream(of: AudioChunk.self, bufferingPolicy: .unbounded)
        let isLast = lock.withLock { () -> Bool in
            continuations[index] = continuation
            return continuations.count == expected
        }
        if isLast {
            await startSource()
        } else {
            try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, Error>) in
                let result = lock.withLock { () -> Result<Void, Error>? in
                    if let startResult { return startResult }
                    waiters.append(waiter)
                    return nil
                }
                if let result { waiter.resume(with: result) }
            }
        }
        if case .failure(let error)? = lock.withLock({ startResult }) { throw error }
        return stream
    }

    private func startSource() async {
        let result: Result<Void, Error>
        do {
            let upstream = try await source.start()
            let task = Task { [weak self] in
                for await chunk in upstream {
                    guard let self else { return }
                    let targets = self.lock.withLock { Array(self.continuations.values) }
                    for target in targets { target.yield(chunk) }
                }
                self?.finishAll()
            }
            lock.withLock { pump = task }
            result = .success(())
        } catch {
            result = .failure(error)
        }
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            startResult = result
            defer { waiters.removeAll() }
            return waiters
        }
        for waiter in pending { waiter.resume(with: result) }
        if case .failure = result { finishAll() }
    }

    /// Fails every branch that is still waiting for the source to start (used when one consumer cannot even begin).
    public func abort(_ error: Error) {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            if startResult == nil { startResult = .failure(error) }
            defer { waiters.removeAll() }
            return waiters
        }
        for waiter in pending { waiter.resume(throwing: error) }
        finishAll()
    }

    private func stopBranch(_ index: Int) async {
        let (all, continuation) = lock.withLock { () -> (Bool, AsyncStream<AudioChunk>.Continuation?) in
            stoppedBranches.insert(index)
            return (stoppedBranches.count >= expected, continuations[index])
        }
        continuation?.finish()
        if all {
            await source.stop()
            let task = lock.withLock { pump }
            task?.cancel()
            finishAll()
        }
    }

    private func finishAll() {
        let all = lock.withLock { Array(continuations.values) }
        for continuation in all { continuation.finish() }
    }
}
