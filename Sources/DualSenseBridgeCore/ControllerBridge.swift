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

/// One pointer-button action together with what the pointer boundary did.
public struct PointerButtonStep: Hashable, Sendable, CustomStringConvertible {
    public let action: PointerButtonAction
    public let outcome: PointerButtonOutcome

    public init(action: PointerButtonAction, outcome: PointerButtonOutcome) {
        self.action = action
        self.outcome = outcome
    }

    public var description: String { "\(action) -> \(outcome)" }
}

/// One navigation output together with what the pointer boundary did about it.
public struct NavigationStep: Hashable, Sendable, CustomStringConvertible {
    public let output: NavigationOutput
    public let outcome: NavigationOutcome

    public init(output: NavigationOutput, outcome: NavigationOutcome) {
        self.output = output
        self.outcome = outcome
    }

    public var description: String { "\(output) -> \(outcome)" }
}

/// A snapshot of bridge state for CLI diagnostics.
///
/// Deliberately contains no file paths, transcripts, or machine identifiers so
/// it is safe to paste into a bug report.
public struct BridgeDiagnostics: Hashable, Sendable {
    public let profileName: String
    public let bindingSummary: [String]
    /// The navigation values actually in effect, so a tuning session can confirm
    /// the file it edited is the file being used.
    public let navigationSummary: [String]
    /// Controllers this bridge has been told about. A report is only as truthful
    /// as its input, so callers must feed in a real snapshot rather than assume
    /// an idle bridge knows about attached hardware.
    public let connectedControllers: [ControllerIdentity]
    public let heldKeys: [String]
    /// Whether a stick is steering right now.
    public let isNavigating: Bool
    public let accessibility: AccessibilityReport

    public init(
        profileName: String,
        bindingSummary: [String],
        navigationSummary: [String],
        connectedControllers: [ControllerIdentity],
        heldKeys: [String],
        isNavigating: Bool,
        accessibility: AccessibilityReport
    ) {
        self.profileName = profileName
        self.bindingSummary = bindingSummary
        self.navigationSummary = navigationSummary
        self.connectedControllers = connectedControllers
        self.heldKeys = heldKeys
        self.isNavigating = isNavigating
        self.accessibility = accessibility
    }

    public var text: String {
        var lines = [
            accessibility.headline,
            "Profile: \(profileName)",
            "Controllers: \(connectedControllers.isEmpty ? "none connected" : connectedControllers.map(\.description).joined(separator: ", "))",
            "Held keys: \(heldKeys.isEmpty ? "none" : heldKeys.joined(separator: ", "))",
            "Sticks: \(isNavigating ? "steering" : "at rest")",
            "Bindings:",
        ]
        lines.append(contentsOf: bindingSummary.map { "  \($0)" })
        lines.append("Navigation:")
        lines.append(contentsOf: navigationSummary.map { "  \($0)" })
        lines.append(contentsOf: accessibility.remediationSteps.enumerated().map { "  \($0.offset + 1). \($0.element)" })
        return lines.joined(separator: "\n")
    }
}

/// Wires normalized controller input to synthetic keyboard and pointer output.
///
/// This is the vertical slice: a fake or real input source feeds `handle`, the
/// pure router and navigation engine decide intent, and the keyboard and pointer
/// boundaries perform it.
///
/// Buttons and sticks take different paths on purpose. A button is an *event*, so
/// `handle` acts on it immediately. A stick is a *position*, so `handle` only
/// records it and `tick` turns held positions into motion; that is the only way a
/// stick the input framework has stopped reporting can keep moving.
///
/// The bridge owns two safety invariants: a stopped bridge holds no keys, and a
/// stopped bridge produces no motion.
public final class ControllerBridge {
    /// How long to stay quiet after reporting a navigation problem. A refused
    /// tick would otherwise print at the tick rate, burying the reason.
    private static let navigationProblemQuietPeriod = 2.0

    private var router: ActionRouter
    private var navigation: NavigationEngine
    private var touchpadNavigation: TouchpadNavigationEngine
    private var pointerButtons = PointerButtonRouter()
    private let keyboard: SyntheticKeyboard
    /// Absent when this bridge has no pointer boundary, in which case stick input
    /// is tracked but nothing is ever emitted.
    private let pointer: SyntheticPointer?
    private let log: ((String) -> Void)?
    private var controllers: [ControllerIdentity] = []
    private var isStopped = false
    private var navigating = false
    private var lastNavigationProblemAt: Double?

    public init(
        profile: ControllerProfile,
        keyboard: SyntheticKeyboard,
        pointer: SyntheticPointer? = nil,
        touchpadSettings: TouchpadNavigationSettings = .default,
        log: ((String) -> Void)? = nil
    ) {
        self.router = ActionRouter(profile: profile)
        self.navigation = NavigationEngine(settings: profile.navigation)
        self.touchpadNavigation = TouchpadNavigationEngine(settings: touchpadSettings)
        self.keyboard = keyboard
        self.pointer = pointer
        self.log = log
    }

    deinit {
        // Last-resort safety net if a caller forgets to shut down. A latched mouse
        // button is at least as bad as a latched key.
        keyboard.releaseAllHeldKeys()
        pointer?.releaseAllPointerButtons()
    }

    /// Controllers currently known to be connected, in connection order.
    public var connectedControllers: [ControllerIdentity] { controllers }

    /// Synthetic keys currently held down.
    public var heldKeys: [KeyCode] { keyboard.heldKeys }

    public var isRunning: Bool { !isStopped }

    /// Whether a stick is currently steering the pointer or scrolling.
    public var isNavigating: Bool { navigating }

    /// How often `tick` should be called, from the active profile.
    ///
    /// This is a preference, not a contract: motion is computed from the elapsed
    /// time a tick reports, so a caller whose timer drifts, coalesces, or does not
    /// exactly match this value still moves at the configured speed.
    public var tickInterval: Double { navigation.settings.tickInterval }

    public var diagnostics: BridgeDiagnostics {
        BridgeDiagnostics(
            profileName: router.profile.name,
            bindingSummary: router.profile.summaryLines,
            navigationSummary: navigation.settings.summaryLines,
            connectedControllers: controllers,
            heldKeys: keyboard.heldKeys.map(\.canonicalName),
            isNavigating: navigating,
            accessibility: keyboard.accessibilityReport
        )
    }

    /// Routes one input and performs the resulting actions.
    @discardableResult
    public func handle(_ input: ControllerInput) -> [BridgeStep] {
        guard !isStopped else { return [] }

        updateControllerList(for: input)
        updateNavigation(for: input)

        if case .axis = input {
            // Axis samples arrive far faster than a person can read, and they
            // produce no keyboard intent, so they are recorded silently and the
            // next tick decides what moves.
            return []
        }

        if case .touchpad(let event) = input {
            performTouchpadNavigation(event)
            return []
        }

        let buttonSteps = performPointerButtons(for: input)
        let steps = router.handle(input).map { action in
            BridgeStep(action: action, outcome: keyboard.perform(action))
        }

        logSteps(steps, pointerButtonSteps: buttonSteps, for: input)
        return steps
    }

    /// Produces the motion owed since the previous tick.
    ///
    /// This is what makes a *held* stick keep moving: the input framework reports
    /// a stick only when its value changes, so nothing but a clock can tell the
    /// difference between "released" and "still pushed".
    @discardableResult
    public func tick(at now: Double) -> [NavigationStep] {
        guard !isStopped, let pointer else { return [] }

        let outputs = navigation.tick(at: now)
        guard !outputs.isEmpty else {
            // Motion just stopped: drop any sub-pixel remainder so the next push
            // starts from rest.
            if navigating {
                pointer.reset()
                navigating = false
            }
            return []
        }

        navigating = true
        let steps = outputs.map { NavigationStep(output: $0, outcome: pointer.perform($0)) }
        logNavigationProblems(in: steps, at: now)
        return steps
    }

    /// Replaces the active profile, releasing anything held under the old one and
    /// stopping any motion the old settings had started.
    @discardableResult
    public func use(profile: ControllerProfile) -> [BridgeStep] {
        guard !isStopped else { return [] }

        let steps = router.replaceProfile(with: profile).map { action in
            BridgeStep(action: action, outcome: keyboard.perform(action))
        }
        navigation.replaceSettings(with: profile.navigation)
        touchpadNavigation.clearAll()
        stopNavigating()
        releaseAllPointerButtons()
        log?("profile \(profile.name)")
        return steps
    }

    /// Stops accepting input, releases every synthetic key still held, and stops
    /// all motion.
    @discardableResult
    public func shutdown() -> [BridgeStep] {
        guard !isStopped else { return [] }

        let steps = router.handle(.shutdown).map { action in
            BridgeStep(action: action, outcome: keyboard.perform(action))
        }
        isStopped = true
        controllers.removeAll()
        navigation.clearAll()
        touchpadNavigation.clearAll()
        stopNavigating()
        releaseAllPointerButtons()
        log?("shutdown")
        // Belt and braces: the routers only know about holds they started.
        keyboard.releaseAllHeldKeys()
        pointer?.releaseAllPointerButtons()
        return steps
    }

    // MARK: - Navigation bookkeeping

    private func updateNavigation(for input: ControllerInput) {
        switch input {
        case .axis(let event):
            navigation.update(event)
        case .touchpad:
            // Touch deltas are performed immediately by `handle`; unlike a held
            // stick they owe no repeated motion on future ticks.
            break
        case .connected(let controller):
            // A reconnect can never inherit motion from a previous session.
            navigation.clear(controller: controller)
            touchpadNavigation.clear(controller: controller)
            stopNavigating()
        case .disconnected(let controller):
            navigation.clear(controller: controller)
            touchpadNavigation.clear(controller: controller)
            stopNavigating()
        case .shutdown:
            navigation.clearAll()
            touchpadNavigation.clearAll()
            stopNavigating()
        case .button:
            break
        }
    }

    private func stopNavigating() {
        pointer?.reset()
        navigating = false
    }

    /// Applies one touch delta immediately. A touch surface reports movement
    /// continuously, so it does not need the timer thumbsticks use.
    private func performTouchpadNavigation(_ event: ControllerTouchpadEvent) {
        let outputs = touchpadNavigation.handle(event)

        if event.phase != .moved {
            log?("touchpad \(event.contact.rawValue) \(event.phase.rawValue) \(event.position)")
        }

        guard let pointer else { return }
        let steps = outputs.map { NavigationStep(output: $0, outcome: pointer.perform($0)) }
        logNavigationProblems(in: steps, at: event.timestamp)

        // Do not carry a fraction of the previous swipe into a new gesture.
        if event.phase == .ended, touchpadNavigation.isIdle {
            pointer.reset()
        }
    }

    // MARK: - Pointer buttons

    /// Forgets every pointer-button owner and releases anything still down.
    private func releaseAllPointerButtons() {
        _ = pointerButtons.releaseEverything()
        pointer?.releaseAllPointerButtons()
    }

    /// Applies whatever the pointer-button router decided.
    ///
    /// Returns the steps so the caller can log them next to the control that
    /// caused them; there is no separate stream to subscribe to.
    private func performPointerButtons(for input: ControllerInput) -> [PointerButtonStep] {
        let actions = pointerButtons.handle(input)
        guard let pointer, !actions.isEmpty else { return [] }
        return actions.map { PointerButtonStep(action: $0, outcome: pointer.perform($0)) }
    }

    /// Reports refusals and sink failures at most once per quiet period.
    private func logNavigationProblems(in steps: [NavigationStep], at now: Double) {
        guard let log else { return }

        let problem = steps.first { step in
            switch step.outcome {
            case .refused, .failed: true
            case .emitted, .accumulated: false
            }
        }
        guard let problem else { return }

        if let last = lastNavigationProblemAt, now - last < Self.navigationProblemQuietPeriod {
            return
        }
        lastNavigationProblemAt = now
        log("navigation \(problem.outcome)")
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
        case .axis, .touchpad, .button, .shutdown:
            break
        }
    }

    private func logSteps(
        _ steps: [BridgeStep],
        pointerButtonSteps: [PointerButtonStep],
        for input: ControllerInput
    ) {
        guard let log else { return }

        let prefix: String
        switch input {
        case .connected(let controller):
            prefix = "connected \(controller)"
        case .disconnected(let controller):
            prefix = "disconnected \(controller)"
        case .button(let event):
            prefix = "\(event.control.rawValue) \(event.phase.rawValue)"
        case .axis(let event):
            // Never reached: axis input returns before routing. Named rather
            // than defaulted so a new input case cannot slip through silently.
            prefix = "\(event.stick.rawValue) stick \(event.position)"
        case .touchpad(let event):
            // Never reached: touchpad input returns immediately after its
            // pointer output. Kept exhaustive so new input kinds cannot hide.
            prefix = "touchpad \(event.contact.rawValue) \(event.phase.rawValue) \(event.position)"
        case .shutdown:
            prefix = "shutdown"
        }

        let descriptions = pointerButtonSteps.map(\.description) + steps.map(\.description)
        if descriptions.isEmpty {
            log(prefix)
        } else {
            for description in descriptions {
                log("\(prefix): \(description)")
            }
        }
    }
}
