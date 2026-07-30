import Foundation

/// What a stick does: steer the pointer or scroll the focused view.
public enum NavigationRole: String, Codable, CaseIterable, Hashable, Sendable {
    case pointer
    case scroll

    /// The label used in diagnostics and in the profile file.
    public var name: String { rawValue }
}

/// Why a navigation value could not be accepted.
///
/// Every case names the field and the accepted range, because a bad value here
/// steers the user's cursor and a silent clamp would hide the mistake.
public enum NavigationSettingsError: Error, Hashable, Sendable, CustomStringConvertible {
    case outOfRange(field: String, value: Double, expected: String)

    public var description: String {
        switch self {
        case .outOfRange(let field, let value, let expected):
            #"Navigation setting "\#(field)" is \#(Self.describe(value)); it must be \#(expected)."#
        }
    }

    private static func describe(_ value: Double) -> String {
        guard value.isFinite else { return "not a finite number" }
        // `Int(_:)` traps on a Double outside Int's range, and a profile is a
        // hand-edited file that may contain any number at all — including one
        // large enough to crash the very code trying to explain why it is wrong.
        // The integer spelling is therefore only used where it is provably safe.
        guard value == value.rounded(), value.magnitude < 1e15 else { return String(value) }
        return String(Int(value))
    }
}

/// How one stick's deflection becomes speed.
///
/// The three knobs are deliberately independent: `deadzone` decides when motion
/// starts, `responseExponent` decides how fine the low end feels, and `speed`
/// decides the top end. Tuning one does not silently move the others.
public struct NavigationAxisSettings: Hashable, Sendable {
    /// Deflection below this magnitude produces nothing at all. A worn stick
    /// rarely returns to exactly zero, so this is what keeps an untouched
    /// controller from drifting the cursor.
    public var deadzone: Double
    /// Exponent applied to the rescaled deflection. 1 is linear; higher values
    /// trade coarse control near the deadzone for finer control overall while
    /// leaving full deflection at full speed.
    public var responseExponent: Double
    /// Units per second at full deflection: screen pixels for the pointer,
    /// scroll pixels for scrolling.
    public var speed: Double
    public var invertX: Bool
    public var invertY: Bool

    public init(
        deadzone: Double,
        responseExponent: Double,
        speed: Double,
        invertX: Bool = false,
        invertY: Bool = false
    ) {
        self.deadzone = deadzone
        self.responseExponent = responseExponent
        self.speed = speed
        self.invertX = invertX
        self.invertY = invertY
    }

    /// The 0...1 fraction of full speed for a given clamped deflection, or 0
    /// inside the deadzone.
    ///
    /// Deflection past the deadzone is rescaled from zero rather than stepped,
    /// so leaving the deadzone does not jerk the cursor.
    func response(forMagnitude magnitude: Double) -> Double {
        guard magnitude > deadzone else { return 0 }
        let usableRange = 1 - deadzone
        guard usableRange > 0 else { return 0 }
        let rescaled = min((magnitude - deadzone) / usableRange, 1)
        return pow(rescaled, responseExponent)
    }

    func validate(field: String) throws {
        try Self.check(deadzone, field: "\(field).deadzone", expected: "0 up to 0.9") {
            $0 >= 0 && $0 < 0.9
        }
        try Self.check(responseExponent, field: "\(field).responseExponent", expected: "between 0.5 and 6") {
            $0 >= 0.5 && $0 <= 6
        }
        try Self.check(speed, field: "\(field).speed", expected: "above 0 and at most 5000") {
            $0 > 0 && $0 <= 5_000
        }
    }

    private static func check(
        _ value: Double,
        field: String,
        expected: String,
        isValid: (Double) -> Bool
    ) throws {
        guard value.isFinite, isValid(value) else {
            throw NavigationSettingsError.outOfRange(field: field, value: value, expected: expected)
        }
    }

    var summary: String {
        let inverted = [invertX ? "invertX" : nil, invertY ? "invertY" : nil].compactMap { $0 }
        let suffix = inverted.isEmpty ? "" : ", " + inverted.joined(separator: ", ")
        return String(
            format: "deadzone %.2f, curve %.2f, %.0f px/s%@",
            deadzone,
            responseExponent,
            speed,
            suffix
        )
    }
}

/// The complete, tunable navigation configuration.
///
/// The stick-to-role assignment is fixed for this slice: the right stick steers
/// the pointer and the left stick scrolls. Swapping roles, and layers more
/// generally, is deliberately deferred (see `docs/prd.md`).
public struct NavigationSettings: Hashable, Sendable {
    /// Responsive pointer defaults with a deliberately gentler scroll speed so
    /// a terminal buffer remains easy to control.
    public static let `default` = NavigationSettings(
        pointer: NavigationAxisSettings(deadzone: 0.15, responseExponent: 2, speed: 2_340),
        scroll: NavigationAxisSettings(deadzone: 0.2, responseExponent: 2, speed: 850),
        // 125 Hz, written as a round number because this file is hand-edited and
        // "0.008333333333333333" invites a typo.
        tickInterval: 0.008,
        maximumTickInterval: 0.05
    )

    /// The right stick.
    public var pointer: NavigationAxisSettings
    /// The left stick.
    public var scroll: NavigationAxisSettings
    /// How often the run loop asks for motion. Smaller is smoother; the cost of
    /// an idle tick is a dictionary check.
    public var tickInterval: Double
    /// The most elapsed time a single tick may account for. This is what stops a
    /// stalled process, a wake from sleep, or a debugger pause from flinging the
    /// cursor across the screen when the loop resumes.
    public var maximumTickInterval: Double

    public init(
        pointer: NavigationAxisSettings,
        scroll: NavigationAxisSettings,
        tickInterval: Double,
        maximumTickInterval: Double
    ) {
        self.pointer = pointer
        self.scroll = scroll
        self.tickInterval = tickInterval
        self.maximumTickInterval = maximumTickInterval
    }

    public func role(of stick: ControllerStick) -> NavigationRole {
        switch stick {
        case .right: .pointer
        case .left: .scroll
        }
    }

    /// The stick that fills a role, which is the inverse of `role(of:)`.
    public func stick(for role: NavigationRole) -> ControllerStick {
        switch role {
        case .pointer: .right
        case .scroll: .left
        }
    }

    func settings(for role: NavigationRole) -> NavigationAxisSettings {
        switch role {
        case .pointer: pointer
        case .scroll: scroll
        }
    }

    public func validate() throws {
        try pointer.validate(field: NavigationRole.pointer.name)
        try scroll.validate(field: NavigationRole.scroll.name)

        guard tickInterval.isFinite, (0.002...0.1).contains(tickInterval) else {
            throw NavigationSettingsError.outOfRange(
                field: "tickInterval",
                value: tickInterval,
                expected: "between 0.002 and 0.1 seconds"
            )
        }
        guard
            maximumTickInterval.isFinite,
            maximumTickInterval >= tickInterval,
            maximumTickInterval <= 1
        else {
            throw NavigationSettingsError.outOfRange(
                field: "maximumTickInterval",
                value: maximumTickInterval,
                expected: "at least tickInterval and at most 1 second"
            )
        }
    }

    /// Human-readable lines for CLI diagnostics, free of machine-specific data.
    public var summaryLines: [String] {
        NavigationRole.allCases.map { role in
            "\(stick(for: role).rawValue) stick -> \(role.name): \(settings(for: role).summary)"
        }
            + [String(format: "tick %.0f Hz, stall clamp %.0f ms", 1 / tickInterval, maximumTickInterval * 1_000)]
    }
}
