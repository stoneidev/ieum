import Foundation

/// The last few replies, newest first, so a good one can be copied again.
public struct ReplyHistory: Equatable, Sendable {
    public struct Item: Equatable, Sendable, Identifiable {
        public var id: String { source }
        public let source: String
        public let reply: String

        public init(source: String, reply: String) {
            self.source = source
            self.reply = reply
        }
    }

    public static let capacity = 5
    public private(set) var items: [Item] = []

    public init() {}

    /// The same sentence asked again replaces the older answer and moves to the top.
    public mutating func add(source: String, reply: String) {
        items.removeAll { $0.source == source }
        items.insert(Item(source: source, reply: reply), at: 0)
        if items.count > Self.capacity { items.removeLast(items.count - Self.capacity) }
    }

    public mutating func clear() { items.removeAll() }
}
