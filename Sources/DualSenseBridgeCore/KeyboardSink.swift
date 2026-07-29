/// A single synthetic key transition.
public enum KeyEmission: Hashable, Sendable, CustomStringConvertible {
    case down(KeyCode)
    case up(KeyCode)

    public var key: KeyCode {
        switch self {
        case .down(let key), .up(let key): key
        }
    }

    public var description: String {
        switch self {
        case .down(let key): "down \(key.canonicalName)"
        case .up(let key): "up \(key.canonicalName)"
        }
    }
}

/// The narrow boundary through which all synthetic keyboard output flows.
///
/// The protocol is deliberately per-physical-key: chords are composed by the
/// caller so that a chord interrupted halfway through can still be unwound key
/// by key.
public protocol KeyboardSink: AnyObject {
    func keyDown(_ key: KeyCode) throws
    func keyUp(_ key: KeyCode) throws
}

/// A sink that records instead of emitting, used by fake-input tests and by the
/// CLI's dry-run mode.
public final class RecordingKeyboardSink: KeyboardSink {
    public private(set) var emissions: [KeyEmission] = []

    public init() {}

    public func keyDown(_ key: KeyCode) throws {
        emissions.append(.down(key))
    }

    public func keyUp(_ key: KeyCode) throws {
        emissions.append(.up(key))
    }

    /// Human-readable emissions for diagnostics.
    public var transcript: [String] {
        emissions.map(\.description)
    }

    public func reset() {
        emissions.removeAll()
    }
}

/// A sink that reports what would have been emitted without emitting anything.
///
/// This backs `dualsense-bridge run --dry-run`, which lets a user verify their
/// bindings before granting Accessibility permission.
public final class LoggingKeyboardSink: KeyboardSink {
    private let log: (String) -> Void

    public init(log: @escaping (String) -> Void) {
        self.log = log
    }

    public func keyDown(_ key: KeyCode) throws {
        log(KeyEmission.down(key).description)
    }

    public func keyUp(_ key: KeyCode) throws {
        log(KeyEmission.up(key).description)
    }
}
