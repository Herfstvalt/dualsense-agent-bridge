/// Sensitivity for relative motion made from absolute DualSense touch samples.
public struct TouchpadNavigationSettings: Hashable, Sendable {
    /// Cursor pixels produced by one normalized unit of finger travel.
    public var pointerPixelsPerUnit: Double
    /// Retained for source compatibility with the first touchpad profile.
    /// Touchpad input is pointer-only now, so this value is intentionally ignored.
    public var scrollPixelsPerUnit: Double

    public init(pointerPixelsPerUnit: Double, scrollPixelsPerUnit: Double) {
        self.pointerPixelsPerUnit = pointerPixelsPerUnit
        self.scrollPixelsPerUnit = scrollPixelsPerUnit
    }

    /// A full-width finger travel is two normalized units, or roughly one laptop
    /// screen at the default sensitivity.
    public static let `default` = TouchpadNavigationSettings(
        pointerPixelsPerUnit: 700,
        scrollPixelsPerUnit: 300
    )
}

/// Converts touch contact deltas into relative cursor motion.
///
/// Every active contact contributes to the touchpad centroid. This keeps a
/// second finger from turning into a scroll/swipe event while preserving a
/// stable cursor if the user briefly touches the surface with more than one
/// finger.
///
/// Contact callbacks drive this engine directly; unlike a thumbstick, a finger
/// only owes motion when its position changes. Began/ended samples establish and
/// remove baselines without output, which prevents a finger landing on the far
/// edge of the pad from teleporting the cursor.
public struct TouchpadNavigationEngine: Sendable {
    private struct ContactKey: Hashable {
        let controller: String
        let contact: TouchpadContact
    }

    public private(set) var settings: TouchpadNavigationSettings
    private var positions: [ContactKey: TouchpadPosition] = [:]

    public init(settings: TouchpadNavigationSettings = .default) {
        self.settings = settings
    }

    public var isIdle: Bool { positions.isEmpty }
    public var activeContactCount: Int { positions.count }

    public mutating func handle(_ event: ControllerTouchpadEvent) -> [NavigationOutput] {
        let key = ContactKey(controller: event.controller.id, contact: event.contact)

        switch event.phase {
        case .began:
            positions[key] = event.position
            return []
        case .ended:
            positions[key] = nil
            return []
        case .moved:
            guard let previous = positions[key] else {
                // Framework fallbacks can miss a down transition. Treat the
                // first position as a baseline instead of jumping from centre.
                positions[key] = event.position
                return []
            }
            positions[key] = event.position

            let dx = event.position.x - previous.x
            let dy = event.position.y - previous.y
            guard dx != 0 || dy != 0 else { return [] }

            // Each contact callback contributes its fraction of the centroid's
            // movement. Finger-up is positive in GameController, so invert y to
            // match the screen's cursor coordinate system. No touchpad sample
            // becomes a wheel or system-swipe event.
            let divisor = Double(max(contactCount(for: event.controller.id), 1))
            return [
                .moveCursor(
                    dx: dx * safe(settings.pointerPixelsPerUnit) / divisor,
                    dy: -dy * safe(settings.pointerPixelsPerUnit) / divisor
                )
            ]
        }
    }

    public mutating func clear(controller: ControllerIdentity) {
        positions = positions.filter { $0.key.controller != controller.id }
    }

    public mutating func clearAll() {
        positions.removeAll()
    }

    private func contactCount(for controller: String) -> Int {
        positions.keys.lazy.filter { $0.controller == controller }.count
    }

    /// Invalid hand-built settings become a bounded no-op rather than a cursor
    /// jump. Stored profiles do not expose these knobs yet.
    private func safe(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 5_000)
    }
}
