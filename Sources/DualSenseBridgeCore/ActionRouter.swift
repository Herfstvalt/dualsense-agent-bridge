/// Keyboard intent produced by the router.
///
/// Actions describe *what* should happen, never *how*; nothing here knows about
/// CoreGraphics, AppKit, or GameController.
public enum BridgeAction: Hashable, Sendable, CustomStringConvertible {
    /// Press and keep holding the shortcut, as press-to-talk requires.
    case beginHold(KeyStroke)
    /// Release a shortcut that `beginHold` started.
    case endHold(KeyStroke)
    /// Emit a complete key-down/key-up pair.
    case tap(KeyStroke)
    /// Release every synthetic key still held, whatever started it.
    case releaseAllHeldKeys
    /// The control has no binding in the active profile. Reported so the CLI
    /// can help a user discover control names, but it emits no keyboard output.
    case unmapped(ControllerControl)

    public var description: String {
        switch self {
        case .beginHold(let stroke): "beginHold(\(stroke))"
        case .endHold(let stroke): "endHold(\(stroke))"
        case .tap(let stroke): "tap(\(stroke))"
        case .releaseAllHeldKeys: "releaseAllHeldKeys"
        case .unmapped(let control): "unmapped(\(control.rawValue))"
        }
    }
}

/// Translates normalized controller input into keyboard intent.
///
/// The router is a value type with no I/O, so a whole session can be replayed
/// in tests. It owns the hold bookkeeping that makes duplicate and out-of-order
/// events harmless and guarantees a disconnect ends every hold it started.
public struct ActionRouter: Sendable {
    private struct HoldKey: Hashable {
        let controller: String
        let control: ControllerControl
    }

    public private(set) var profile: ControllerProfile
    private var activeHolds: [HoldKey: KeyStroke] = [:]

    public init(profile: ControllerProfile) {
        self.profile = profile
    }

    /// How many controls are currently considered held. Exposed for diagnostics
    /// and for tests that assert cleanup actually happened.
    public var heldControlCount: Int { activeHolds.count }

    /// The shortcuts the router believes are currently held, in stable order.
    public var heldStrokes: [KeyStroke] {
        activeHolds
            .sorted { ($0.key.controller, $0.key.control.rawValue) < ($1.key.controller, $1.key.control.rawValue) }
            .map(\.value)
    }

    public mutating func handle(_ input: ControllerInput) -> [BridgeAction] {
        switch input {
        case .button(let event):
            return handle(event)
        case .axis:
            // Stick axes never produce keyboard intent. They are navigation, and
            // the navigation engine owns them, so a stick can be held through a
            // dictation hold without disturbing it.
            return []
        case .connected(let controller):
            // A reconnect can never inherit holds from a previous session. This
            // is scoped rather than global precisely because it does not sweep.
            return endHolds(for: controller)
        case .disconnected(let controller):
            // The leaving controller's holds end first so the log reads in the
            // right order, then every remaining hold ends too: the sweep below
            // releases every physical key, so keeping any hold recorded would
            // leave the router claiming a key that is no longer down.
            return endHolds(for: controller) + endAllHolds() + [.releaseAllHeldKeys]
        case .shutdown:
            return endAllHolds() + [.releaseAllHeldKeys]
        }
    }

    /// Swaps the active profile, ending anything currently held first so a
    /// mapping change cannot leave a key latched.
    public mutating func replaceProfile(with profile: ControllerProfile) -> [BridgeAction] {
        let cleanup = endAllHolds() + [.releaseAllHeldKeys]
        self.profile = profile
        return cleanup
    }

    // MARK: - Button handling

    private mutating func handle(_ event: ControllerEvent) -> [BridgeAction] {
        let key = HoldKey(controller: event.controller.id, control: event.control)

        guard let binding = profile.binding(for: event.control) else {
            // A control the pointer already speaks for is not unbound, so shrugging
            // at it would tell the user R2 does nothing while it is in fact holding
            // the right mouse button down. Note this suppresses only the shrug: an
            // explicit binding below is still honored, because silently ignoring a
            // mapping someone wrote on purpose would be the worse trap.
            guard event.control != PointerButtonRouter.rightButtonControl else { return [] }
            // Only report on press so a shrug does not appear twice per button.
            return event.phase.isPressed ? [.unmapped(event.control)] : []
        }

        switch (binding, event.phase) {
        case (.tap(let stroke), .pressed):
            return [.tap(stroke)]
        case (.tap, .released):
            return []
        case (.hold(let stroke), .pressed):
            // A duplicate press must not emit a second key-down; the key is
            // already down and only one release will follow.
            guard activeHolds[key] == nil else { return [] }
            activeHolds[key] = stroke
            return [.beginHold(stroke)]
        case (.hold, .released):
            // A release with no recorded press is harmless by construction.
            guard let stroke = activeHolds.removeValue(forKey: key) else { return [] }
            return [.endHold(stroke)]
        }
    }

    // MARK: - Cleanup

    private mutating func endHolds(for controller: ControllerIdentity) -> [BridgeAction] {
        let keys = activeHolds.keys
            .filter { $0.controller == controller.id }
            .sorted { $0.control.rawValue < $1.control.rawValue }

        return keys.compactMap { key in
            activeHolds.removeValue(forKey: key).map { BridgeAction.endHold($0) }
        }
    }

    private mutating func endAllHolds() -> [BridgeAction] {
        let keys = activeHolds.keys
            .sorted { ($0.controller, $0.control.rawValue) < ($1.controller, $1.control.rawValue) }
        return keys.compactMap { key in
            activeHolds.removeValue(forKey: key).map { BridgeAction.endHold($0) }
        }
    }
}
