import Foundation

/// One of the two contacts the DualSense touch surface can track.
public enum TouchpadContact: String, Codable, CaseIterable, Hashable, Sendable {
    case primary
    case secondary
}

/// The lifecycle of one finger on the touch surface.
public enum TouchpadPhase: String, Codable, Hashable, Sendable {
    case began
    case moved
    case ended
}

/// An absolute, normalized point on the DualSense touch surface.
///
/// GameController reports both axes in `-1...1`, with y positive up. Keeping
/// that convention at the input boundary lets the navigation engine make the
/// one deliberate conversion to macOS screen and scrolling coordinates.
public struct TouchpadPosition: Hashable, Sendable, CustomStringConvertible {
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

    public var description: String {
        String(format: "x=%+.2f y=%+.2f", x, y)
    }
}

/// One normalized touch contact sample.
public struct ControllerTouchpadEvent: Hashable, Sendable {
    public let controller: ControllerIdentity
    public let contact: TouchpadContact
    public let phase: TouchpadPhase
    public let position: TouchpadPosition
    public let timestamp: Double
    public let source: ControllerEventSource

    public init(
        controller: ControllerIdentity,
        contact: TouchpadContact,
        phase: TouchpadPhase,
        position: TouchpadPosition,
        timestamp: Double,
        source: ControllerEventSource
    ) {
        self.controller = controller
        self.contact = contact
        self.phase = phase
        self.position = position
        self.timestamp = timestamp
        self.source = source
    }
}
