#if os(macOS)
import Foundation
import GameController

/// The process-global GameController operations the event source depends on.
///
/// Only global state is behind this seam, so a test can prove that background
/// monitoring is enabled before discovery starts without a paired controller.
@MainActor
protocol ControllerDiscoveryHost: AnyObject {
    /// Whether controller input is delivered while this process is not the
    /// frontmost application.
    var monitorsBackgroundEvents: Bool { get set }

    func startDiscovery()
    func stopDiscovery()
}

/// The real GameController global state.
///
/// `shouldMonitorBackgroundEvents` is a class property that defaults to false on
/// macOS 11.3 and newer whenever the process is not frontmost, so a CLI bridge
/// has to opt in explicitly.
@MainActor
final class GameControllerDiscoveryHost: ControllerDiscoveryHost {
    var monitorsBackgroundEvents: Bool {
        get { GCController.shouldMonitorBackgroundEvents }
        set { GCController.shouldMonitorBackgroundEvents = newValue }
    }

    func startDiscovery() {
        GCController.startWirelessControllerDiscovery()
    }

    func stopDiscovery() {
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
    private var isStarted = false
    /// The background-monitoring value to put back on stop, when this source is
    /// the one that changed it.
    private var backgroundEventSettingToRestore: Bool?

    public convenience init() {
        self.init(host: GameControllerDiscoveryHost())
    }

    init(host: any ControllerDiscoveryHost) {
        self.host = host
    }

    /// Starts observing connections and button transitions.
    ///
    /// Calling this while already started does nothing, so notification
    /// observers and discovery are never installed twice.
    public func start(handler: @escaping Handler) {
        guard !isStarted else { return }
        isStarted = true
        self.handler = handler

        // Order matters. Background monitoring must be on before any controller
        // is observed, attached, or discovered: a controller that attaches while
        // background monitoring is off delivers no input at all.
        enableBackgroundEvents()
        observeConnections()
        synchronizeControllers()
        host.startDiscovery()
    }

    /// Stops observing and puts back any process-global state it changed.
    ///
    /// Does nothing if the source was never started, so there is nothing to
    /// undo. Callers are still responsible for shutting the bridge down so held
    /// keys are released.
    public func stop() {
        guard isStarted else { return }
        isStarted = false

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
    }

    // MARK: - Background events

    /// Allows controller input while this process is in the background.
    ///
    /// The bridge normally stays behind the target terminal or text field.
    /// Since macOS 11.3, GameController drops every button event for a process
    /// that is not frontmost unless this is enabled, which looks exactly like a
    /// controller that connects and then does nothing.
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

        // Thumbsticks report only when their value *changes*, so a stick held at
        // full deflection goes quiet after one callback. These handlers therefore
        // report position, and the navigation tick supplies the motion.
        for (stick, pad) in Self.mappedSticks(of: gamepad) {
            pad.valueChangedHandler = { [weak self] _, x, y in
                MainActor.assumeIsolated {
                    self?.emit(stick, x: Double(x), y: Double(y), from: identity)
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
        for (_, pad) in Self.mappedSticks(of: gamepad) {
            pad.valueChangedHandler = nil
        }
    }

    private func emit(_ stick: ControllerStick, x: Double, y: Double, from identity: ControllerIdentity) {
        handler?(
            .axis(
                ControllerAxisEvent(
                    controller: identity,
                    stick: stick,
                    position: StickVector(x: x, y: y),
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    source: .gameController
                )
            )
        )
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

    private static func mappedSticks(
        of gamepad: GCExtendedGamepad
    ) -> [(ControllerStick, GCControllerDirectionPad)] {
        [
            (.left, gamepad.leftThumbstick),
            (.right, gamepad.rightThumbstick),
        ]
    }
}
#endif
