import Foundation

/// Tracks the changeCount values produced by our own copy/paste so the monitor
/// can skip re-capturing them. Extracted from PasteService's former static set.
/// Thread-safe; a `.shared` instance is used in production.
final class SelfPasteTracker: @unchecked Sendable {
    static let shared = SelfPasteTracker()

    private let lock = NSLock()
    private var suppressed = Set<Int>()
    private let maxEntries: Int

    init(maxEntries: Int = 200) { self.maxEntries = maxEntries }

    /// Mark the inclusive range [begin, end] as self-produced.
    func markRange(begin: Int, end: Int) {
        guard begin <= end else { return }
        lock.withLock {
            suppressed.formUnion(begin...end)
            if suppressed.count > maxEntries { suppressed.removeAll() }
        }
    }

    /// Returns true and consumes the value when `changeCount` was self-produced.
    func shouldSuppress(changeCount: Int) -> Bool {
        lock.withLock {
            if suppressed.contains(changeCount) {
                suppressed.remove(changeCount)
                return true
            }
            return false
        }
    }

    func reset() { lock.withLock { suppressed.removeAll() } }
}
