/// What happened when an action reached the keyboard boundary.
public enum KeyboardOutcome: Hashable, Sendable, CustomStringConvertible {
    /// The action produced synthetic key events.
    case emitted
    /// The action was understood but needed no key events.
    case noOutput
    /// Output was withheld because the Accessibility capability is unavailable.
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
/// Held keys are reference counted, so two holds that share a modifier do not
/// fight over it, and a sweep can always unwind in reverse press order.
public final class SyntheticKeyboard {
    private static let sinkFailureReason = "the keyboard sink rejected a synthetic key event"

    private let sink: any KeyboardSink
    private let accessibility: AccessibilityCapability

    /// Keys currently down, oldest first, with a press count per key.
    private var pressOrder: [KeyCode] = []
    private var pressCounts: [KeyCode: Int] = [:]
    /// Physical keys owed to each active hold, so ending one hold releases
    /// exactly what that hold contributed.
    private var holdContributions: [KeyStroke: [KeyCode]] = [:]

    public init(sink: any KeyboardSink, accessibility: AccessibilityCapability) {
        self.sink = sink
        self.accessibility = accessibility
    }

    /// Keys the bridge believes are held, in press order.
    public var heldKeys: [KeyCode] { pressOrder }

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
        if case .unmapped = action { return .noOutput }

        let report = accessibilityReport
        guard report.isUsable else {
            return .refused(reason: report.headline)
        }

        switch action {
        case .tap(let stroke):
            return tap(stroke)
        case .beginHold(let stroke):
            return beginHold(stroke)
        case .endHold(let stroke):
            return endHold(stroke)
        case .releaseAllHeldKeys:
            return pressOrder.isEmpty ? .noOutput : sweep()
        case .unmapped:
            return .noOutput
        }
    }

    /// Releases everything still held. Safe to call during shutdown even when
    /// permission has since been revoked; bookkeeping is cleared either way.
    public func releaseAllHeldKeys() {
        guard !pressOrder.isEmpty else { return }
        _ = sweep()
    }

    // MARK: - Actions

    private func tap(_ stroke: KeyStroke) -> KeyboardOutcome {
        var pressed: [KeyCode] = []
        for key in stroke.physicalKeysInPressOrder {
            guard press(key) else {
                unwind(pressed)
                return .failed(reason: Self.sinkFailureReason)
            }
            pressed.append(key)
        }
        unwind(pressed)
        return .emitted
    }

    private func beginHold(_ stroke: KeyStroke) -> KeyboardOutcome {
        guard holdContributions[stroke] == nil else { return .noOutput }

        var pressed: [KeyCode] = []
        for key in stroke.physicalKeysInPressOrder {
            guard press(key) else {
                unwind(pressed)
                return .failed(reason: Self.sinkFailureReason)
            }
            pressed.append(key)
        }
        holdContributions[stroke] = pressed
        return .emitted
    }

    private func endHold(_ stroke: KeyStroke) -> KeyboardOutcome {
        guard let pressed = holdContributions.removeValue(forKey: stroke) else {
            return .noOutput
        }
        return unwind(pressed) ? .emitted : .failed(reason: Self.sinkFailureReason)
    }

    /// Releases every held key in reverse press order and forgets all holds.
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

    private func press(_ key: KeyCode) -> Bool {
        let alreadyDown = (pressCounts[key] ?? 0) > 0
        if !alreadyDown {
            do {
                try sink.keyDown(key)
            } catch {
                return false
            }
            pressOrder.append(key)
        }
        pressCounts[key, default: 0] += 1
        return true
    }

    /// Releases the given keys in reverse order, honoring reference counts.
    @discardableResult
    private func unwind(_ keys: [KeyCode]) -> Bool {
        var succeeded = true
        for key in keys.reversed() {
            guard let count = pressCounts[key], count > 0 else { continue }
            if count == 1 {
                do { try sink.keyUp(key) } catch { succeeded = false }
                pressCounts[key] = nil
                if let index = pressOrder.lastIndex(of: key) {
                    pressOrder.remove(at: index)
                }
            } else {
                pressCounts[key] = count - 1
            }
        }
        return succeeded
    }
}
