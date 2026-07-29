import Foundation

@testable import DualSenseBridgeCore

/// A thread-safe, mutable Accessibility status for tests that need permission to
/// change while a chord is being held.
///
/// `AccessibilityCapability` reads its status through a `@Sendable` closure, so
/// capturing a mutable local and reassigning it afterwards is a data race that
/// Swift 6 warns about. This helper owns the value behind a lock instead, which
/// keeps the seam warning-free without weakening the concurrency checks.
final class MutableAccessibility: @unchecked Sendable {
    private let lock = NSLock()
    private var status: AccessibilityStatus

    init(_ status: AccessibilityStatus) {
        self.status = status
    }

    /// The current status, safe to read from any thread.
    var current: AccessibilityStatus {
        lock.lock()
        defer { lock.unlock() }
        return status
    }

    func set(_ status: AccessibilityStatus) {
        lock.lock()
        defer { lock.unlock() }
        self.status = status
    }

    func grant() {
        set(.granted)
    }

    func revoke() {
        set(.denied)
    }

    /// A capability that re-reads the live value on every check, exactly as the
    /// system capability does.
    var capability: AccessibilityCapability {
        AccessibilityCapability { [self] in current }
    }
}

/// A thread-safe collector for log lines produced by a bridge under test.
final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(line)
    }
}
