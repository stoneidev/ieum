import Foundation

/// A dotted app version such as "0.2.10", compared number by number ("0.2.10" is newer than "0.2.9").
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        let numbers = text.split(separator: ".").map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil }) else { return nil }
        parts = numbers.compactMap { $0 }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

/// Which release highlights to show when the app starts.
public enum WhatsNew {
    /// Users who finished the setup before this feature existed have no recorded version; they are treated as coming from here.
    public static let baseline = "0.2.3"

    /// Indices (in the order given) of the highlights introduced after the version the person last saw, up to the running one.
    /// - A first install shows none: the setup window is the welcome.
    /// - Nothing is shown again for the same version, after a downgrade, or when a version cannot be read.
    public static func pending(introduced: [String], lastSeen: String?, current: String, isFirstInstall: Bool) -> [Int] {
        guard !isFirstInstall, let current = AppVersion(current) else { return [] }
        guard let seen = AppVersion(lastSeen ?? baseline) else { return [] }
        return introduced.indices.filter { index in
            guard let version = AppVersion(introduced[index]) else { return false }
            return version > seen && version <= current
        }
    }
}
