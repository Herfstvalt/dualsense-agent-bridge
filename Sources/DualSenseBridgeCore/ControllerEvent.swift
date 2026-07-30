/// A connected controller, identified without referencing any input framework.
public struct ControllerIdentity: Hashable, Sendable, CustomStringConvertible {
    /// A stable identifier for the physical device within one bridge session.
    public let id: String
    /// A human-readable name suitable for diagnostics.
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    public var description: String { "\(displayName) (\(id))" }
}

/// A physical control on a DualSense controller.
///
/// Raw values are the names accepted in profile configuration files.
public enum ControllerControl: String, Codable, CaseIterable, Hashable, Sendable {
    case cross, circle, square, triangle
    case l1, r1, l2, r2, l3, r3
    case dpadUp, dpadDown, dpadLeft, dpadRight
    case options, create, psButton, touchpadButton
    /// The DualSense hardware mic button, reserved for hardware mute by default.
    case micButton
}

/// Whether a control went down or came back up.
public enum ControllerEventPhase: String, Codable, Hashable, Sendable {
    case pressed
    case released

    public var isPressed: Bool { self == .pressed }
}

/// Where a normalized event came from, so diagnostics can distinguish real
/// hardware from a fake harness.
public enum ControllerEventSource: String, Codable, Hashable, Sendable {
    case gameController
    case rawHID
    case fake
}

/// A normalized button transition.
public struct ControllerEvent: Hashable, Sendable {
    public let controller: ControllerIdentity
    public let control: ControllerControl
    public let phase: ControllerEventPhase
    /// Seconds on the source's monotonic clock. Kept as a plain number so the
    /// model has no dependency on a date provider.
    public let timestamp: Double
    public let source: ControllerEventSource

    public init(
        controller: ControllerIdentity,
        control: ControllerControl,
        phase: ControllerEventPhase,
        timestamp: Double,
        source: ControllerEventSource
    ) {
        self.controller = controller
        self.control = control
        self.phase = phase
        self.timestamp = timestamp
        self.source = source
    }
}

/// Everything the action router can be told about the input world, including
/// lifecycle changes. Disconnect is part of the stream so held-key cleanup is
/// driven by the same code path as ordinary input.
public enum ControllerInput: Hashable, Sendable {
    case connected(ControllerIdentity)
    case disconnected(ControllerIdentity)
    case button(ControllerEvent)
    /// A thumbstick moved to a new normalized position. Unlike a button, this
    /// says where the stick *is*, not that something happened, because a held
    /// stick keeps steering long after its last sample.
    case axis(ControllerAxisEvent)
    /// A finger began, moved, or ended on the DualSense touch surface.
    case touchpad(ControllerTouchpadEvent)
    /// The bridge itself is stopping.
    case shutdown

    /// The controller this input concerns, if any.
    public var controller: ControllerIdentity? {
        switch self {
        case .connected(let controller), .disconnected(let controller):
            controller
        case .button(let event):
            event.controller
        case .axis(let event):
            event.controller
        case .touchpad(let event):
            event.controller
        case .shutdown:
            nil
        }
    }
}
