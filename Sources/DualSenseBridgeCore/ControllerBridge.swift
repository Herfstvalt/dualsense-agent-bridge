/// One routed action together with what the keyboard boundary did about it.
public struct BridgeStep: Hashable, Sendable, CustomStringConvertible {
    public let action: BridgeAction
    public let outcome: KeyboardOutcome

    public init(action: BridgeAction, outcome: KeyboardOutcome) {
        self.action = action
        self.outcome = outcome
    }

    public var description: String { "\(action) -> \(outcome)" }
}

/// A snapshot of bridge state for CLI diagnostics.
///
/// Deliberately contains no file paths, transcripts, or machine identifiers so
/// it is safe to paste into a bug report.
public struct BridgeDiagnostics: Hashable, Sendable {
    public let profileName: String
    public let bindingSummary: [String]
    /// Controllers this bridge has been told about. A report is only as truthful
    /// as its input, so callers must feed in a real snapshot rather than assume
    /// an idle bridge knows about attached hardware.
    public let connectedControllers: [ControllerIdentity]
    public let heldKeys: [String]
    public let accessibility: AccessibilityReport

    public var text: String {
        var lines = [
            accessibility.headline,
            "Profile: \(profileName)",
            "Controllers: \(connectedControllers.isEmpty ? "none connected" : connectedControllers.map(\.description).joined(separator: ", "))",
            "Held keys: \(heldKeys.isEmpty ? "none" : heldKeys.joined(separator: ", "))",
            "Bindings:",
        ]
        lines.append(contentsOf: bindingSummary.map { "  \($0)" })
        lines.append(contentsOf: accessibility.remediationSteps.enumerated().map { "  \($0.offset + 1). \($0.element)" })
        return lines.joined(separator: "\n")
    }
}

/// Wires normalized controller input to synthetic keyboard output.
///
/// This is the vertical slice: a fake or real input source feeds `handle`, the
/// pure router decides intent, and the keyboard boundary performs it. The bridge
/// owns the safety invariant that a stopped bridge holds no keys.
public final class ControllerBridge {
    private var router: ActionRouter
    private let keyboard: SyntheticKeyboard
    private let log: ((String) -> Void)?
    private var controllers: [ControllerIdentity] = []
    private var isStopped = false

    public init(
        profile: ControllerProfile,
        keyboard: SyntheticKeyboard,
        log: ((String) -> Void)? = nil
    ) {
        self.router = ActionRouter(profile: profile)
        self.keyboard = keyboard
        self.log = log
    }

    deinit {
        // Last-resort safety net if a caller forgets to shut down.
        keyboard.releaseAllHeldKeys()
    }

    /// Controllers currently known to be connected, in connection order.
    public var connectedControllers: [ControllerIdentity] { controllers }

    /// Synthetic keys currently held down.
    public var heldKeys: [KeyCode] { keyboard.heldKeys }

    public var isRunning: Bool { !isStopped }

    public var diagnostics: BridgeDiagnostics {
        BridgeDiagnostics(
            profileName: router.profile.name,
            bindingSummary: router.profile.summaryLines,
            connectedControllers: controllers,
            heldKeys: keyboard.heldKeys.map(\.canonicalName),
            accessibility: keyboard.accessibilityReport
        )
    }

    /// Routes one input and performs the resulting actions.
    @discardableResult
    public func handle(_ input: ControllerInput) -> [BridgeStep] {
        guard !isStopped else { return [] }

        updateControllerList(for: input)

        let steps = router.handle(input).map { action in
            BridgeStep(action: action, outcome: keyboard.perform(action))
        }

        logSteps(steps, for: input)
        return steps
    }

    /// Replaces the active profile, releasing anything held under the old one.
    @discardableResult
    public func use(profile: ControllerProfile) -> [BridgeStep] {
        guard !isStopped else { return [] }

        let steps = router.replaceProfile(with: profile).map { action in
            BridgeStep(action: action, outcome: keyboard.perform(action))
        }
        log?("profile \(profile.name)")
        return steps
    }

    /// Stops accepting input and releases every synthetic key still held.
    @discardableResult
    public func shutdown() -> [BridgeStep] {
        guard !isStopped else { return [] }

        let steps = router.handle(.shutdown).map { action in
            BridgeStep(action: action, outcome: keyboard.perform(action))
        }
        isStopped = true
        controllers.removeAll()
        log?("shutdown")
        // Belt and braces: the router only knows about holds it started.
        keyboard.releaseAllHeldKeys()
        return steps
    }

    // MARK: - Bookkeeping

    private func updateControllerList(for input: ControllerInput) {
        switch input {
        case .connected(let controller):
            if !controllers.contains(controller) {
                controllers.append(controller)
            }
        case .disconnected(let controller):
            controllers.removeAll { $0 == controller }
        case .button, .shutdown:
            break
        }
    }

    private func logSteps(_ steps: [BridgeStep], for input: ControllerInput) {
        guard let log else { return }

        let prefix: String
        switch input {
        case .connected(let controller):
            prefix = "connected \(controller)"
        case .disconnected(let controller):
            prefix = "disconnected \(controller)"
        case .button(let event):
            prefix = "\(event.control.rawValue) \(event.phase.rawValue)"
        case .shutdown:
            prefix = "shutdown"
        }

        if steps.isEmpty {
            log(prefix)
        } else {
            for step in steps {
                log("\(prefix): \(step)")
            }
        }
    }
}
