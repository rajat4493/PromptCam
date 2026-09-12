import Foundation

/// Time source for a recording session.
///
/// Named `SessionClock` rather than `Clock` to avoid colliding with the Swift
/// standard library's `Clock` protocol.
///
/// Every duration and marker offset in PromptCam derives from this, so tests
/// produce exact timestamps without waiting in real time.
public protocol SessionClock: Sendable {
    var now: Date { get }
}

/// The real clock, used by the app.
public struct SystemSessionClock: SessionClock {
    public init() {}
    public var now: Date { Date() }
}

/// A clock the tests drive by hand.
///
/// Marker-accuracy tests depend on this: advance by exactly 12.5 seconds and
/// the marker offset must be exactly 12.5.
public final class ManualSessionClock: SessionClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    public init(start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.current = start
    }

    public var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    /// Moves time forward by `seconds`.
    public func advance(by seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }

    public func set(to date: Date) {
        lock.lock()
        current = date
        lock.unlock()
    }
}
