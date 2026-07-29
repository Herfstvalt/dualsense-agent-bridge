#if os(macOS)
import Foundation
import GameController

/// The real GameController global state.
///
/// `shouldMonitorBackgroundEvents` is a class property that defaults to false on
/// macOS 11.3 and newer whenever the process is not frontmost, so a CLI bridge
/// has to opt in explicitly.
@MainActor
public final class GameControllerDiscoveryHost: ControllerDiscoveryHost {
    public init() {}

    public var monitorsBackgroundEvents: Bool {
        get { GCController.shouldMonitorBackgroundEvents }
        set { GCController.shouldMonitorBackgroundEvents = newValue }
    }

    public func startDiscovery() {
        GCController.startWirelessControllerDiscovery()
    }

    public func stopDiscovery() {
        GCController.stopWirelessControllerDiscovery()
    }
}

/// Normalizes GameController input into `ControllerInput`.
///
/// This is the only file that knows GameController exists. Everything above it
/// works from the framework-independent event model, which is what lets the
/// whole action path be tested with a fake input harness.
///
/// The DualSense hardware mic button is not exposed by GameController; raw-HID
/// support for it is deliberately deferred (see `docs/prd.md`).
@MainActor
public final class GameControllerEventSource {
    public typealias Handler = (ControllerInput) -> Void

    private let host: any ControllerDiscoveryHost
    private var handler: Handler?
    private var observers: [any NSObjectProtocol] = []
    private var identities: [ObjectIdentifier: ControllerIdentity] = [:]
    private var nextIndex = 1
    /// The background-monitoring value to put back on stop, when this source is
    /// the one that changed it.
    private var backgroundEventSettingToRestore: Bool?
    /// The startup steps this source actually performed, in order.
    public private(set) var startupSteps: [ControllerSourceStartupStep] = []

    public init(host: any ControllerDiscoveryHost = GameControllerDiscoveryHost()) {
        self.host = host
    }

    /// Starts observing connections and button transitions.
    ///
    /// Steps run in `ControllerSourceStartupPlan` order so background monitoring
    /// is enabled before any controller is observed, attached, or discovered.
    public func start(handler: @escaping Handler) {
        self.handler = handler
        startupSteps.removeAll()

        for step in ControllerSourceStartupPlan.steps {
            perform(step)
            startupSteps.append(step)
        }
    }

    /// Stops observing and puts back any process-global state it changed.
    ///
    /// Callers are still responsible for shutting the bridge down so held keys
    /// are released.
    public func stop() {
        host.stopDiscovery()
        restoreBackgroundEvents()

        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()

        for controller in GCController.controllers() {
            clearHandlers(controller)
        }
        identities.removeAll()
        handler = nil
        startupSteps.removeAll()
    }

    // MARK: - Startup steps

    private func perform(_ step: ControllerSourceStartupStep) {
        switch step {
        case .enableBackgroundEvents:
            enableBackgroundEvents()
        case .observeConnections:
            observeConnections()
        case .attachExistingControllers:
            synchronizeControllers()
        case .startWirelessDiscovery:
            host.startDiscovery()
        }
    }

    /// Allows controller input while this process is in the background.
    ///
    /// A bridge started over SSH, from a background terminal, or from a tmux
    /// window is never the frontmost application. Since macOS 11.3 that means
    /// GameController drops every button event unless this is enabled, which
    /// looks exactly like a controller that connects and then does nothing.
    private func enableBackgroundEvents() {
        guard !host.monitorsBackgroundEvents else { return }
        // Only remember a value this source is responsible for putting back.
        backgroundEventSettingToRestore = false
        host.monitorsBackgroundEvents = true
    }

    private func restoreBackgroundEvents() {
        guard let previous = backgroundEventSettingToRestore else { return }
        host.monitorsBackgroundEvents = previous
        backgroundEventSettingToRestore = nil
    }

    private func observeConnections() {
        let center = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            // The notification payload is intentionally ignored: re-reading
            // `GCController.controllers()` keeps every framework object on the
            // main actor instead of passing it across an isolation boundary.
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.synchronizeControllers()
                    }
                }
            )
        }
    }

    /// Controllers currently attached to this running source.
    public var attachedControllers: [ControllerIdentity] {
        identities.values.sorted { $0.id < $1.id }
    }

    /// Whether controller input is currently delivered while this process is in
    /// the background. Surfaced so `run` can state it plainly: when this is
    /// false, a controller can connect and still produce no input.
    public var monitorsBackgroundEvents: Bool {
        host.monitorsBackgroundEvents
    }

    /// Reports the controllers GameController sees right now, without starting
    /// the source or installing any handlers.
    ///
    /// `doctor` uses this so its controller line reflects reality instead of an
    /// idle bridge that was never told about anything. Controllers that are
    /// paired but powered off are correctly absent.
    public static func connectedControllerSnapshot() -> [ControllerIdentity] {
        GCController.controllers()
            .filter { $0.extendedGamepad != nil }
            .enumerated()
            .map { index, controller in
                ControllerIdentity(
                    id: "controller-\(index + 1)",
                    displayName: controller.vendorName ?? "Game Controller"
                )
            }
    }

    // MARK: - Attachment

    /// Reconciles the tracked controllers with what GameController reports.
    private func synchronizeControllers() {
        let current = GCController.controllers()
        let currentKeys = Set(current.map(ObjectIdentifier.init))

        for key in identities.keys where !currentKeys.contains(key) {
            if let identity = identities.removeValue(forKey: key) {
                handler?(.disconnected(identity))
            }
        }
        for controller in current {
            attach(controller)
        }
    }

    /// Attaches button handlers once per controller and announces it.
    private func attach(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }

        let box = ObjectIdentifier(controller)
        guard identities[box] == nil else { return }

        let identity = ControllerIdentity(
            id: "controller-\(nextIndex)",
            displayName: controller.vendorName ?? "Game Controller"
        )
        identities[box] = identity
        nextIndex += 1

        for (control, button) in Self.mappedButtons(of: gamepad) {
            button.pressedChangedHandler = { [weak self] _, _, pressed in
                MainActor.assumeIsolated {
                    self?.emit(control, pressed: pressed, from: identity)
                }
            }
        }

        handler?(.connected(identity))
    }

    private func clearHandlers(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        for (_, button) in Self.mappedButtons(of: gamepad) {
            button.pressedChangedHandler = nil
        }
    }

    private func emit(_ control: ControllerControl, pressed: Bool, from identity: ControllerIdentity) {
        handler?(
            .button(
                ControllerEvent(
                    controller: identity,
                    control: control,
                    phase: pressed ? .pressed : .released,
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    source: .gameController
                )
            )
        )
    }

    // MARK: - Mapping

    private static func mappedButtons(
        of gamepad: GCExtendedGamepad
    ) -> [(ControllerControl, GCControllerButtonInput)] {
        var buttons: [(ControllerControl, GCControllerButtonInput)] = [
            (.cross, gamepad.buttonA),
            (.circle, gamepad.buttonB),
            (.square, gamepad.buttonX),
            (.triangle, gamepad.buttonY),
            (.l1, gamepad.leftShoulder),
            (.r1, gamepad.rightShoulder),
            (.l2, gamepad.leftTrigger),
            (.r2, gamepad.rightTrigger),
            (.dpadUp, gamepad.dpad.up),
            (.dpadDown, gamepad.dpad.down),
            (.dpadLeft, gamepad.dpad.left),
            (.dpadRight, gamepad.dpad.right),
            (.options, gamepad.buttonMenu),
        ]

        if let create = gamepad.buttonOptions {
            buttons.append((.create, create))
        }
        if let home = gamepad.buttonHome {
            buttons.append((.psButton, home))
        }
        if let leftThumbstick = gamepad.leftThumbstickButton {
            buttons.append((.l3, leftThumbstick))
        }
        if let rightThumbstick = gamepad.rightThumbstickButton {
            buttons.append((.r3, rightThumbstick))
        }
        if let dualSense = gamepad as? GCDualSenseGamepad {
            buttons.append((.touchpadButton, dualSense.touchpadButton))
        }

        return buttons
    }
}
#endif
