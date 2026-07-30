import Foundation

/// Pointer intent produced by the navigation engine.
///
/// Deltas are fractional units for the tick that produced them; turning them
/// into whole pixels is the pointer boundary's job, so slow motion is not lost
/// to rounding.
public enum NavigationOutput: Hashable, Sendable, CustomStringConvertible {
    /// Move the cursor by a relative amount, in screen pixels, y growing down.
    case moveCursor(dx: Double, dy: Double)
    /// Scroll the focused view, in scroll pixels, y positive up.
    case scroll(dx: Double, dy: Double)

    public var description: String {
        switch self {
        case .moveCursor(let dx, let dy): String(format: "moveCursor dx=%+.2f dy=%+.2f", dx, dy)
        case .scroll(let dx, let dy): String(format: "scroll dx=%+.2f dy=%+.2f", dx, dy)
        }
    }
}

/// Turns held stick positions into bounded motion, one tick at a time.
///
/// The engine is a value type with no I/O and no clock of its own, which is what
/// makes the whole feel of the mapping testable: a test advances the clock by
/// hand and asserts exact deltas.
///
/// Two properties matter more than the arithmetic:
///
/// - Motion is driven by `tick`, not by axis callbacks. GameController reports a
///   stick only when its value *changes*, so a stick held at full deflection
///   goes quiet; anything driven by callbacks alone would move once and stop.
/// - A tick can never account for more than `maximumTickInterval`, so a stalled
///   or suspended process resumes gently instead of flinging the cursor.
public struct NavigationEngine: Sendable {
    private struct AxisKey: Hashable, Comparable {
        let controller: String
        let stick: ControllerStick

        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.controller, lhs.stick.rawValue) < (rhs.controller, rhs.stick.rawValue)
        }
    }

    public private(set) var settings: NavigationSettings
    /// Only axes outside their deadzone are kept, so an idle controller costs
    /// nothing and "is anything moving?" is a single check.
    private var activeAxes: [AxisKey: StickVector] = [:]
    private var lastTickTime: Double?

    public init(settings: NavigationSettings = .default) {
        self.settings = settings
    }

    /// Whether any stick is currently deflected past its deadzone.
    public var isIdle: Bool { activeAxes.isEmpty }

    /// How many axes are currently steering, for diagnostics and tests.
    public var activeAxisCount: Int { activeAxes.count }

    /// Records where a stick now rests.
    ///
    /// A sample inside the deadzone removes the axis outright, which is what
    /// makes "let go and it stops" a property of the data rather than a timer.
    public mutating func update(_ event: ControllerAxisEvent) {
        let key = AxisKey(controller: event.controller.id, stick: event.stick)
        let axis = settings.settings(for: settings.role(of: event.stick))

        if axis.response(forMagnitude: event.position.magnitude) > 0 {
            activeAxes[key] = event.position
        } else {
            activeAxes[key] = nil
        }
    }

    /// Produces the motion owed for the time since the previous tick.
    ///
    /// The first call only establishes the clock baseline: with no previous tick
    /// there is no elapsed time to convert into travel.
    public mutating func tick(at now: Double) -> [NavigationOutput] {
        defer { lastTickTime = now }

        guard let previous = lastTickTime, !activeAxes.isEmpty else { return [] }
        let elapsed = min(max(now - previous, 0), settings.maximumTickInterval)
        guard elapsed > 0 else { return [] }

        // Roles are emitted in a fixed order, and controllers within a role in
        // id order, so a log or a test never depends on dictionary ordering.
        return NavigationRole.allCases.flatMap { role in
            activeAxes
                .filter { settings.role(of: $0.key.stick) == role }
                .sorted { $0.key < $1.key }
                .compactMap { output(for: role, position: $0.value, elapsed: elapsed) }
        }
    }

    /// Forgets every axis of one controller, without touching another
    /// controller's motion.
    public mutating func clear(controller: ControllerIdentity) {
        activeAxes = activeAxes.filter { $0.key.controller != controller.id }
    }

    /// Forgets every axis. Used on shutdown, where nothing may keep moving.
    public mutating func clearAll() {
        activeAxes.removeAll()
    }

    /// Swaps the tuning, stopping all motion first so a settings change cannot
    /// leave the cursor gliding under values that no longer apply.
    public mutating func replaceSettings(with settings: NavigationSettings) {
        clearAll()
        self.settings = settings
    }

    // MARK: - Arithmetic

    private func output(
        for role: NavigationRole,
        position: StickVector,
        elapsed: Double
    ) -> NavigationOutput? {
        let axis = settings.settings(for: role)
        let response = axis.response(forMagnitude: position.magnitude)
        guard response > 0 else { return nil }

        // Speed comes from the clamped magnitude and direction from the raw one,
        // so a diagonal travels at the configured speed rather than 1.41 times it.
        let distance = response * axis.speed * elapsed
        let direction = position.direction
        let dx = direction.x * distance * (axis.invertX ? -1 : 1)
        let stickDY = direction.y * distance * (axis.invertY ? -1 : 1)

        switch role {
        case .pointer:
            // Screen coordinates grow downwards, so pushing the stick up must
            // subtract from y.
            return .moveCursor(dx: dx, dy: -stickDY)
        case .scroll:
            // Scrolling keeps the stick's sign: pushing up scrolls up.
            return .scroll(dx: dx, dy: stickDY)
        }
    }
}
