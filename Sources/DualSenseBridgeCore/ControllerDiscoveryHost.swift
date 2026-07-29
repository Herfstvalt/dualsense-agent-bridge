/// The process-global controller operations a controller source depends on.
///
/// Only global state lives here; individual controller objects stay inside the
/// platform adapter. That keeps the ordering rule below testable without a
/// paired controller, which matters because getting the order wrong produces a
/// bridge that reports a controller and then silently receives nothing.
@MainActor
public protocol ControllerDiscoveryHost: AnyObject {
    /// Whether controller input is delivered while this process is not the
    /// frontmost application.
    var monitorsBackgroundEvents: Bool { get set }

    func startDiscovery()
    func stopDiscovery()
}

/// A step a controller source performs while starting up.
public enum ControllerSourceStartupStep: Hashable, Sendable, CustomStringConvertible {
    /// Allow input while the process is in the background.
    case enableBackgroundEvents
    /// Observe connect and disconnect notifications.
    case observeConnections
    /// Attach controllers that are already connected.
    case attachExistingControllers
    /// Begin looking for wireless controllers.
    case startWirelessDiscovery

    public var description: String {
        switch self {
        case .enableBackgroundEvents: "enableBackgroundEvents"
        case .observeConnections: "observeConnections"
        case .attachExistingControllers: "attachExistingControllers"
        case .startWirelessDiscovery: "startWirelessDiscovery"
        }
    }
}

/// The order in which a controller source must start up.
///
/// Background monitoring is enabled first, before any controller is observed,
/// attached, or discovered. A bridge launched over SSH or from a background
/// terminal is never the frontmost application, and on macOS 11.3 and newer
/// `GCController.shouldMonitorBackgroundEvents` defaults to false in that case,
/// so a controller attached before the switch is flipped delivers no input at
/// all: it connects, and then every button press is dropped.
public enum ControllerSourceStartupPlan {
    public static let steps: [ControllerSourceStartupStep] = [
        .enableBackgroundEvents,
        .observeConnections,
        .attachExistingControllers,
        .startWirelessDiscovery,
    ]
}
