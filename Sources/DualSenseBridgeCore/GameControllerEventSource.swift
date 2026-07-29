#if os(macOS)
import Foundation
import GameController

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

    private var handler: Handler?
    private var observers: [any NSObjectProtocol] = []
    private var identities: [ObjectIdentifier: ControllerIdentity] = [:]
    private var nextIndex = 1

    public init() {}

    /// Starts observing connections and button transitions.
    public func start(handler: @escaping Handler) {
        self.handler = handler

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

        synchronizeControllers()
        GCController.startWirelessControllerDiscovery()
    }

    /// Stops observing. Callers are still responsible for shutting the bridge
    /// down so held keys are released.
    public func stop() {
        GCController.stopWirelessControllerDiscovery()
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

    /// Controllers currently attached to this running source.
    public var attachedControllers: [ControllerIdentity] {
        identities.values.sorted { $0.id < $1.id }
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
