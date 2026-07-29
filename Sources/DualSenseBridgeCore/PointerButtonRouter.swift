/// Pointer-button intent produced by the pointer-button router.
///
/// Kept separate from `BridgeAction` because it crosses a different boundary: a
/// keyboard sink can do nothing with a mouse button, and a pointer sink can do
/// nothing with a keystroke.
public enum PointerButtonAction: Hashable, Sendable, CustomStringConvertible {
    case pressRightButton
    case releaseRightButton
    /// Release every pointer button still down, whatever started it.
    case releaseAllPointerButtons

    public var description: String {
        switch self {
        case .pressRightButton: "pressRightButton"
        case .releaseRightButton: "releaseRightButton"
        case .releaseAllPointerButtons: "releaseAllPointerButtons"
        }
    }
}

/// Decides when the right mouse button goes down and comes back up.
///
/// R2 is reserved for the right mouse button rather than being a profile
/// binding, so this router needs no configuration at all.
///
/// Ownership is per controller, which is the whole reason this is a type and not
/// a boolean: with two controllers paired, one letting go of R2 must not lift a
/// button the other is still holding. That also makes duplicate and out-of-order
/// transitions harmless, because a set records *who* holds the button rather
/// than *how many times* it was pressed.
public struct PointerButtonRouter: Sendable {
    /// The control reserved for the right mouse button.
    public static let rightButtonControl: ControllerControl = .r2

    private var rightButtonOwners: Set<String> = []

    public init() {}

    /// Whether any controller is holding the right button down.
    public var isRightButtonHeld: Bool { !rightButtonOwners.isEmpty }

    /// How many controllers are holding it, for diagnostics and tests.
    public var rightButtonOwnerCount: Int { rightButtonOwners.count }

    public mutating func handle(_ input: ControllerInput) -> [PointerButtonAction] {
        switch input {
        case .button(let event) where event.control == Self.rightButtonControl:
            return event.phase.isPressed
                ? press(owner: event.controller.id)
                : release(owner: event.controller.id)
        case .connected(let controller):
            // A reconnect can never inherit a hold from a previous session.
            return release(owner: controller.id)
        case .disconnected(let controller):
            // Scoped, not a sweep: unlike the keyboard path there is only one
            // physical button here, and a second controller still pressing R2 is
            // legitimately still holding it down.
            return release(owner: controller.id)
        case .shutdown:
            return releaseEverything()
        case .button, .axis:
            return []
        }
    }

    /// Forgets every owner and asks the boundary to sweep.
    ///
    /// Used for shutdown and profile replacement, where nothing may stay down and
    /// the router's own bookkeeping is not to be trusted over the physical state.
    public mutating func releaseEverything() -> [PointerButtonAction] {
        rightButtonOwners.removeAll()
        return [.releaseAllPointerButtons]
    }

    private mutating func press(owner: String) -> [PointerButtonAction] {
        let wasHeld = isRightButtonHeld
        rightButtonOwners.insert(owner)
        // A duplicate press must not emit a second button-down; the button is
        // already down and only one release will follow.
        return wasHeld ? [] : [.pressRightButton]
    }

    private mutating func release(owner: String) -> [PointerButtonAction] {
        // A release with no recorded press is harmless by construction.
        guard rightButtonOwners.remove(owner) != nil else { return [] }
        return rightButtonOwners.isEmpty ? [.releaseRightButton] : []
    }
}
