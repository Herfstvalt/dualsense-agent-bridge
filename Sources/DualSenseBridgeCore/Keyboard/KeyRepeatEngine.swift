/// Timing for a controller button that behaves like a held keyboard key.
public struct KeyRepeatSettings: Hashable, Sendable {
    /// Time between the initial key-down and the first repeat event.
    public var initialDelay: Double
    /// Time between later repeat events.
    public var interval: Double

    public init(initialDelay: Double, interval: Double) {
        precondition(initialDelay.isFinite && initialDelay >= 0)
        precondition(interval.isFinite && interval > 0)
        self.initialDelay = initialDelay
        self.interval = interval
    }

    /// Deliberately close to the ordinary macOS keyboard feel without making a
    /// held delete key so fast that an accidental press destroys a whole line.
    public static let `default` = KeyRepeatSettings(initialDelay: 0.4, interval: 0.05)
}

/// Tracks repeat-capable controls while leaving physical key ownership to
/// `SyntheticKeyboard`.
struct KeyRepeatEngine: Sendable {
    struct Owner: Hashable, Sendable {
        let controller: String
        let control: ControllerControl
    }

    private struct ActiveRepeat: Sendable {
        let stroke: KeyStroke
        var nextRepeatAt: Double
    }

    let settings: KeyRepeatSettings
    private var active: [Owner: ActiveRepeat] = [:]

    init(settings: KeyRepeatSettings = .default) {
        self.settings = settings
    }

    var count: Int { active.count }

    var strokes: [KeyStroke] {
        sortedOwners.compactMap { active[$0]?.stroke }
    }

    mutating func start(owner: Owner, stroke: KeyStroke, at timestamp: Double) -> [BridgeAction] {
        guard active[owner] == nil else { return [] }
        active[owner] = ActiveRepeat(
            stroke: stroke,
            nextRepeatAt: timestamp + settings.initialDelay
        )
        return [.beginHold(stroke)]
    }

    mutating func stop(owner: Owner) -> [BridgeAction] {
        guard let repeatState = active.removeValue(forKey: owner) else { return [] }
        return [.endHold(repeatState.stroke)]
    }

    /// Emits at most one repeat per owner per tick. After a sleep or debugger
    /// pause this deliberately resumes from `now` instead of replaying a burst
    /// of every delete that would have happened while the process was stalled.
    mutating func tick(at now: Double) -> [BridgeAction] {
        var actions: [BridgeAction] = []
        for owner in sortedOwners {
            guard var repeatState = active[owner] else { continue }
            let tolerance = repeatState.nextRepeatAt.ulp * 4
            guard now >= repeatState.nextRepeatAt - tolerance else { continue }

            actions.append(.repeatHeld(repeatState.stroke))
            repeatState.nextRepeatAt = now + settings.interval
            active[owner] = repeatState
        }
        return actions
    }

    mutating func stop(controller: ControllerIdentity) -> [BridgeAction] {
        let owners = sortedOwners.filter { $0.controller == controller.id }
        return owners.flatMap { stop(owner: $0) }
    }

    mutating func stopAll() -> [BridgeAction] {
        sortedOwners.flatMap { stop(owner: $0) }
    }

    private var sortedOwners: [Owner] {
        active.keys.sorted {
            ($0.controller, $0.control.rawValue) < ($1.controller, $1.control.rawValue)
        }
    }
}
