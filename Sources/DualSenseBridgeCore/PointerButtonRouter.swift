/// A physical mouse button the bridge can hold.
public enum PointerButton: String, CaseIterable, Hashable, Sendable, CustomStringConvertible {
    case left
    case right

    public var description: String { rawValue }
}

/// Pointer-button intent produced by the pointer-button router.
///
/// Kept separate from `BridgeAction` because it crosses a different boundary: a
/// keyboard sink can do nothing with a mouse button, and a pointer sink can do
/// nothing with a keystroke.
public enum PointerButtonAction: Hashable, Sendable, CustomStringConvertible {
    case pressLeftButton
    case releaseLeftButton
    case pressRightButton
    case releaseRightButton
    /// Release every pointer button still down, whatever started it.
    case releaseAllPointerButtons

    public var description: String {
        switch self {
        case .pressLeftButton: "pressLeftButton"
        case .releaseLeftButton: "releaseLeftButton"
        case .pressRightButton: "pressRightButton"
        case .releaseRightButton: "releaseRightButton"
        case .releaseAllPointerButtons: "releaseAllPointerButtons"
        }
    }
}

/// Decides when either mouse button goes down and comes back up.
///
/// R2 is reserved for the left mouse button and L2 for the right mouse button
/// rather than being profile bindings, so this router needs no configuration.
///
/// Ownership is per controller, which is the whole reason this is a type and not
/// a boolean: with two controllers paired, one letting go of R2 must not lift a
/// button the other is still holding. That also makes duplicate and out-of-order
/// transitions harmless, because a set records *who* holds the button rather
/// than *how many times* it was pressed.
public struct PointerButtonRouter: Sendable {
    /// The control reserved for the left mouse button.
    public static let leftButtonControl: ControllerControl = .r2
    /// The control reserved for the right mouse button.
    public static let rightButtonControl: ControllerControl = .l2
    /// Controls spoken for by the pointer boundary rather than the keyboard.
    public static let reservedControls: Set<ControllerControl> = [.r2, .l2]

    private var leftButtonOwners: Set<String> = []
    private var rightButtonOwners: Set<String> = []

    public init() {}

    /// Whether any controller is holding the right button down.
    public var isRightButtonHeld: Bool { !rightButtonOwners.isEmpty }

    /// Whether any controller is holding the left button down.
    public var isLeftButtonHeld: Bool { !leftButtonOwners.isEmpty }

    /// How many controllers are holding it, for diagnostics and tests.
    public var rightButtonOwnerCount: Int { rightButtonOwners.count }

    /// How many controllers are holding the left button.
    public var leftButtonOwnerCount: Int { leftButtonOwners.count }

    public mutating func handle(_ input: ControllerInput) -> [PointerButtonAction] {
        switch input {
        case .button(let event) where event.control == Self.leftButtonControl:
            return event.phase.isPressed
                ? pressLeft(owner: event.controller.id)
                : releaseLeft(owner: event.controller.id)
        case .button(let event) where event.control == Self.rightButtonControl:
            return event.phase.isPressed
                ? pressRight(owner: event.controller.id)
                : releaseRight(owner: event.controller.id)
        case .connected(let controller):
            // A reconnect can never inherit a hold from a previous session.
            return releaseLeft(owner: controller.id) + releaseRight(owner: controller.id)
        case .disconnected(let controller):
            // Scoped, not a sweep: a second controller still pressing either
            // button is legitimately still holding it down.
            return releaseLeft(owner: controller.id) + releaseRight(owner: controller.id)
        case .shutdown:
            return releaseEverything()
        case .button, .axis, .touchpad:
            return []
        }
    }

    /// Forgets every owner and asks the boundary to sweep.
    ///
    /// Used for shutdown and profile replacement, where nothing may stay down and
    /// the router's own bookkeeping is not to be trusted over the physical state.
    public mutating func releaseEverything() -> [PointerButtonAction] {
        leftButtonOwners.removeAll()
        rightButtonOwners.removeAll()
        return [.releaseAllPointerButtons]
    }

    private mutating func pressLeft(owner: String) -> [PointerButtonAction] {
        let wasHeld = isLeftButtonHeld
        leftButtonOwners.insert(owner)
        return wasHeld ? [] : [.pressLeftButton]
    }

    private mutating func releaseLeft(owner: String) -> [PointerButtonAction] {
        guard leftButtonOwners.remove(owner) != nil else { return [] }
        return leftButtonOwners.isEmpty ? [.releaseLeftButton] : []
    }

    private mutating func pressRight(owner: String) -> [PointerButtonAction] {
        let wasHeld = isRightButtonHeld
        rightButtonOwners.insert(owner)
        // A duplicate press must not emit a second button-down; the button is
        // already down and only one release will follow.
        return wasHeld ? [] : [.pressRightButton]
    }

    private mutating func releaseRight(owner: String) -> [PointerButtonAction] {
        // A release with no recorded press is harmless by construction.
        guard rightButtonOwners.remove(owner) != nil else { return [] }
        return rightButtonOwners.isEmpty ? [.releaseRightButton] : []
    }
}
