import Testing

@testable import DualSenseBridgeCore

/// Records the process-global controller operations in the order they happen.
@MainActor
final class FakeDiscoveryHost: ControllerDiscoveryHost {
    enum Operation: Hashable, CustomStringConvertible {
        case setMonitorsBackgroundEvents(Bool)
        case startDiscovery
        case stopDiscovery

        var description: String {
            switch self {
            case .setMonitorsBackgroundEvents(let value): "monitorsBackgroundEvents = \(value)"
            case .startDiscovery: "startDiscovery"
            case .stopDiscovery: "stopDiscovery"
            }
        }
    }

    private(set) var operations: [Operation] = []
    private var storedValue: Bool

    init(monitorsBackgroundEvents: Bool = false) {
        storedValue = monitorsBackgroundEvents
    }

    var monitorsBackgroundEvents: Bool {
        get { storedValue }
        set {
            storedValue = newValue
            operations.append(.setMonitorsBackgroundEvents(newValue))
        }
    }

    func startDiscovery() {
        operations.append(.startDiscovery)
    }

    func stopDiscovery() {
        operations.append(.stopDiscovery)
    }
}

@Suite("controller startup enables background events before it looks for input")
struct ControllerSourceStartupPlanTests {
    @Test("background events are enabled before anything is attached or discovered")
    func backgroundEventsComeFirst() throws {
        let steps = ControllerSourceStartupPlan.steps

        let enableIndex = try #require(steps.firstIndex(of: .enableBackgroundEvents))
        let attachIndex = try #require(steps.firstIndex(of: .attachExistingControllers))
        let discoveryIndex = try #require(steps.firstIndex(of: .startWirelessDiscovery))
        let observeIndex = try #require(steps.firstIndex(of: .observeConnections))

        // A controller attached before the switch is flipped would deliver no
        // input at all while the process is in the background.
        #expect(enableIndex == 0)
        #expect(enableIndex < observeIndex)
        #expect(enableIndex < attachIndex)
        #expect(enableIndex < discoveryIndex)
    }

    @Test("the plan covers every startup step exactly once")
    func planIsComplete() {
        let steps = ControllerSourceStartupPlan.steps

        #expect(Set(steps).count == steps.count)
        #expect(
            Set(steps) == [
                .enableBackgroundEvents,
                .observeConnections,
                .attachExistingControllers,
                .startWirelessDiscovery,
            ]
        )
    }
}

@Suite("the GameController source works while the process is in the background")
@MainActor
struct GameControllerEventSourceTests {
    @Test("starting enables background events before discovery begins")
    func startEnablesBackgroundEventsFirst() {
        let host = FakeDiscoveryHost(monitorsBackgroundEvents: false)
        let source = GameControllerEventSource(host: host)

        source.start { _ in }

        // This is the regression: a bridge launched over SSH is never frontmost,
        // so without this the controller reports connected and then nothing else.
        #expect(host.monitorsBackgroundEvents)
        #expect(host.operations == [.setMonitorsBackgroundEvents(true), .startDiscovery])
        #expect(source.startupSteps == ControllerSourceStartupPlan.steps)

        source.stop()
    }

    @Test("stopping restores the previous global setting and stops discovery")
    func stopRestoresPreviousSetting() {
        let host = FakeDiscoveryHost(monitorsBackgroundEvents: false)
        let source = GameControllerEventSource(host: host)

        source.start { _ in }
        source.stop()

        #expect(!host.monitorsBackgroundEvents, "process-global state must not leak")
        #expect(
            host.operations == [
                .setMonitorsBackgroundEvents(true),
                .startDiscovery,
                .stopDiscovery,
                .setMonitorsBackgroundEvents(false),
            ]
        )
    }

    @Test("a host that already monitors background events is left alone")
    func alreadyEnabledHostIsUntouched() {
        let host = FakeDiscoveryHost(monitorsBackgroundEvents: true)
        let source = GameControllerEventSource(host: host)

        source.start { _ in }
        source.stop()

        #expect(host.monitorsBackgroundEvents)
        #expect(host.operations == [.startDiscovery, .stopDiscovery])
    }

    @Test("stopping without starting changes no global state")
    func stopWithoutStartIsSafe() {
        let host = FakeDiscoveryHost(monitorsBackgroundEvents: false)
        let source = GameControllerEventSource(host: host)

        source.stop()

        #expect(!host.monitorsBackgroundEvents)
        #expect(host.operations == [.stopDiscovery])
    }

    @Test("repeated start and stop cycles keep restoring the original value")
    func repeatedCyclesRestoreEachTime() {
        let host = FakeDiscoveryHost(monitorsBackgroundEvents: false)
        let source = GameControllerEventSource(host: host)

        for _ in 0..<3 {
            source.start { _ in }
            #expect(host.monitorsBackgroundEvents)
            source.stop()
            #expect(!host.monitorsBackgroundEvents)
        }
    }

    @Test("starting twice does not lose the value that must be restored")
    func doubleStartStillRestores() {
        let host = FakeDiscoveryHost(monitorsBackgroundEvents: false)
        let source = GameControllerEventSource(host: host)

        source.start { _ in }
        source.start { _ in }
        source.stop()

        #expect(!host.monitorsBackgroundEvents)
    }

    @Test("no controller is reported when none is attached")
    func noControllersWithoutHardware() {
        let host = FakeDiscoveryHost()
        let source = GameControllerEventSource(host: host)
        let collector = LineCollector()

        source.start { collector.append("\($0)") }
        defer { source.stop() }

        // The test machine has no controller bound to this process, so the only
        // observable effect of starting is the global setup above.
        #expect(source.attachedControllers.isEmpty)
    }
}
