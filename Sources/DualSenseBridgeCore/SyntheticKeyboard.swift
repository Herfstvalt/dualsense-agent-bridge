/// What happened when an action reached the keyboard boundary.
public enum KeyboardOutcome: Hashable, Sendable, CustomStringConvertible {
    /// The action produced synthetic key events.
    case emitted
    /// The action was applied but needed no key events, either because there
    /// was nothing to do or because another owner already holds the chord.
    case noOutput
    /// Output was withheld because the Accessibility capability is unavailable.
    /// Only actions that press keys can be refused; cleanup never is.
    case refused(reason: String)
    /// The sink rejected an event; anything partially pressed was released.
    case failed(reason: String)

    public var isRefusal: Bool {
        if case .refused = self { return true }
        return false
    }

    public var description: String {
        switch self {
        case .emitted: "emitted"
        case .noOutput: "no output"
        case .refused(let reason): "refused: \(reason)"
        case .failed(let reason): "failed: \(reason)"
        }
    }
}

/// Applies routed actions to a keyboard sink while guaranteeing that every key
/// it presses is eventually released.
///
/// Two invariants drive this type:
///
/// - Physical keys are reference counted, so several holds may share a chord (or
///   a modifier) without fighting over it, and a sweep can always unwind in
///   reverse press order.
/// - Releasing is never gated on Accessibility permission. Permission can be
///   revoked while a chord is down, and refusing the release would latch a key
///   on the user's machine.
public final class SyntheticKeyboard {
    private static let sinkFailureReason = "the keyboard sink rejected a synthetic key event"

    private enum PressResult {
        case emitted
        case alreadyDown
        case failed
    }

    private let sink: any KeyboardSink
    private let accessibility: AccessibilityCapability

    /// Keys currently down, oldest first, with a press count per key.
    private var pressOrder: [KeyCode] = []
    private var pressCounts: [KeyCode: Int] = [:]
    /// Physical keys owed to each active hold. A stroke maps to one entry per
    /// active owner, so two controls or two controllers bound to the same
    /// shortcut release independently.
    private var holdContributions: [KeyStroke: [[KeyCode]]] = [:]

    public init(sink: any KeyboardSink, accessibility: AccessibilityCapability) {
        self.sink = sink
        self.accessibility = accessibility
    }

    /// Keys the bridge believes are held, in press order.
    public var heldKeys: [KeyCode] { pressOrder }

    /// How many hold owners are currently tracked, for diagnostics and tests.
    public var heldOwnerCount: Int {
        holdContributions.values.reduce(0) { $0 + $1.count }
    }

    /// The current permission report, for CLI diagnostics.
    public var accessibilityReport: AccessibilityReport {
        AccessibilityReport(status: accessibility.status)
    }

    @discardableResult
    public func performAll(_ actions: [BridgeAction]) -> [KeyboardOutcome] {
        actions.map(perform)
    }

    @discardableResult
    public func perform(_ action: BridgeAction) -> KeyboardOutcome {
        switch action {
        case .unmapped:
            return .noOutput
        case .tap(let stroke):
            if let refusal = pressRefusal() { return refusal }
            return tap(stroke)
        case .beginHold(let stroke):
            if let refusal = pressRefusal() { return refusal }
            return beginHold(stroke)
        case .endHold(let stroke):
            // Never refused: a chord that is already down must come back up.
            return endHold(stroke)
        case .releaseAllHeldKeys:
            guard !pressOrder.isEmpty || !holdContributions.isEmpty else { return .noOutput }
            return sweep()
        }
    }

    /// Releases everything still held. Safe to call during shutdown even when
    /// permission has since been revoked; bookkeeping is cleared either way.
    public func releaseAllHeldKeys() {
        guard !pressOrder.isEmpty || !holdContributions.isEmpty else { return }
        _ = sweep()
    }

    // MARK: - Permission

    /// A refusal for actions that would press a key, or nil when allowed.
    private func pressRefusal() -> KeyboardOutcome? {
        let report = accessibilityReport
        guard report.isUsable else { return .refused(reason: report.headline) }
        return nil
    }

    // MARK: - Actions

    private func tap(_ stroke: KeyStroke) -> KeyboardOutcome {
        var pressed: [KeyCode] = []
        for key in stroke.physicalKeysInPressOrder {
            switch press(key) {
            case .emitted, .alreadyDown:
                pressed.append(key)
            case .failed:
                _ = unwind(pressed)
                return .failed(reason: Self.sinkFailureReason)
            }
        }
        let result = unwind(pressed)
        return result.succeeded ? .emitted : .failed(reason: Self.sinkFailureReason)
    }

    private func beginHold(_ stroke: KeyStroke) -> KeyboardOutcome {
        var pressed: [KeyCode] = []
        var emittedAnything = false

        for key in stroke.physicalKeysInPressOrder {
            switch press(key) {
            case .emitted:
                emittedAnything = true
                pressed.append(key)
            case .alreadyDown:
                pressed.append(key)
            case .failed:
                _ = unwind(pressed)
                return .failed(reason: Self.sinkFailureReason)
            }
        }

        holdContributions[stroke, default: []].append(pressed)
        return emittedAnything ? .emitted : .noOutput
    }

    private func endHold(_ stroke: KeyStroke) -> KeyboardOutcome {
        guard var owners = holdContributions[stroke], let pressed = owners.popLast() else {
            return .noOutput
        }
        if owners.isEmpty {
            holdContributions[stroke] = nil
        } else {
            holdContributions[stroke] = owners
        }

        let result = unwind(pressed)
        guard result.succeeded else { return .failed(reason: Self.sinkFailureReason) }
        return result.released ? .emitted : .noOutput
    }

    /// Releases every held key in reverse press order and forgets all owners.
    private func sweep() -> KeyboardOutcome {
        let keys = pressOrder
        holdContributions.removeAll()
        pressOrder.removeAll()
        pressCounts.removeAll()

        var succeeded = true
        for key in keys.reversed() {
            // Continue past failures: a stuck key must not block the rest.
            do { try sink.keyUp(key) } catch { succeeded = false }
        }
        return succeeded ? .emitted : .failed(reason: Self.sinkFailureReason)
    }

    // MARK: - Held-key bookkeeping

    private func press(_ key: KeyCode) -> PressResult {
        let alreadyDown = (pressCounts[key] ?? 0) > 0
        if !alreadyDown {
            do {
                try sink.keyDown(key)
            } catch {
                return .failed
            }
            pressOrder.append(key)
        }
        pressCounts[key, default: 0] += 1
        return alreadyDown ? .alreadyDown : .emitted
    }

    /// Releases the given keys in reverse order, honoring reference counts.
    /// Reports whether any key physically came up and whether the sink agreed.
    private func unwind(_ keys: [KeyCode]) -> (released: Bool, succeeded: Bool) {
        var released = false
        var succeeded = true

        for key in keys.reversed() {
            guard let count = pressCounts[key], count > 0 else { continue }
            if count == 1 {
                do {
                    try sink.keyUp(key)
                    released = true
                } catch {
                    succeeded = false
                }
                pressCounts[key] = nil
                if let index = pressOrder.lastIndex(of: key) {
                    pressOrder.remove(at: index)
                }
            } else {
                pressCounts[key] = count - 1
            }
        }

        return (released, succeeded)
    }
}
