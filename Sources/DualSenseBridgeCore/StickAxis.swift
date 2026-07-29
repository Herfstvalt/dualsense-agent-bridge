import Foundation

/// One of the two analog thumbsticks, named as profile configuration names it.
public enum ControllerStick: String, Codable, CaseIterable, Hashable, Sendable {
    case left
    case right
}

/// A normalized thumbstick position.
///
/// Both components are clamped to `-1...1` with `y` positive **up**, matching the
/// convention every gamepad API uses and deliberately *not* the screen's
/// downward-growing y axis; the conversion happens once, in the navigation
/// engine.
///
/// Non-finite values are neutralized on the way in. A NaN that reached the
/// cursor would move it to an unrecoverable position, and hardware, drivers, and
/// arithmetic on stale samples can all produce one.
public struct StickVector: Hashable, Sendable, CustomStringConvertible {
    /// A stick at rest.
    public static let centered = StickVector(x: 0, y: 0)

    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = Self.normalize(x)
        self.y = Self.normalize(y)
    }

    private static func normalize(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, -1), 1)
    }

    /// Distance from center, clamped to 1 so a diagonal push is not faster than
    /// a cardinal one.
    public var magnitude: Double {
        min(hypot(x, y), 1)
    }

    /// The direction of the push as a unit-length vector, or `.centered` at rest.
    ///
    /// This is deliberately normalized by the *unclamped* length: dividing by
    /// the clamped magnitude would leave a full diagonal 1.41 times longer than
    /// a full cardinal push, which is exactly the bug that makes stick-driven
    /// cursors feel fast on the diagonals.
    public var direction: StickVector {
        let length = hypot(x, y)
        guard length > 0 else { return .centered }
        return StickVector(x: x / length, y: y / length)
    }

    public var isCentered: Bool { x == 0 && y == 0 }

    public var description: String {
        String(format: "x=%+.2f y=%+.2f", x, y)
    }
}

/// A normalized thumbstick sample.
///
/// The shape mirrors `ControllerEvent` so both live in the same input stream and
/// the same fake harness can produce either.
public struct ControllerAxisEvent: Hashable, Sendable {
    public let controller: ControllerIdentity
    public let stick: ControllerStick
    public let position: StickVector
    /// Seconds on the source's monotonic clock, the same clock the navigation
    /// tick uses.
    public let timestamp: Double
    public let source: ControllerEventSource

    public init(
        controller: ControllerIdentity,
        stick: ControllerStick,
        position: StickVector,
        timestamp: Double,
        source: ControllerEventSource
    ) {
        self.controller = controller
        self.stick = stick
        self.position = position
        self.timestamp = timestamp
        self.source = source
    }
}
