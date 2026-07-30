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

@Suite("the controller source works while the process is in the background")
@MainActor
struct GameControllerEventSourceTests {
    @Test("surface motion is opt-in while button routing remains available")
    func surfaceMotionIsOptIn() {
        let host = FakeDiscoveryHost()
        let source = GameControllerEventSource(host: host)

        #expect(!source.surfaceMotionEnabled)
    }

    @Test("background monitoring is enabled before discovery starts")
    func backgroundEventsAreEnabledFirst() {
        let host = FakeDiscoveryHost(monitorsBackgroundEvents: false)
        let source = GameControllerEventSource(host: host)
        defer { source.stop() }

        source.start { _ in }

        // The regression: a bridge launched over SSH is never frontmost, so
        // without this the controller reports connected and then nothing else.
        #expect(host.monitorsBackgroundEvents)
        #expect(host.operations == [.setMonitorsBackgroundEvents(true), .startDiscovery])
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

    @Test("stopping without starting does nothing")
    func stopWithoutStartIsSafe() {
        let host = FakeDiscoveryHost(monitorsBackgroundEvents: false)
        let source = GameControllerEventSource(host: host)

        source.stop()

        #expect(!host.monitorsBackgroundEvents)
        #expect(host.operations.isEmpty)
    }

    @Test("starting twice does not enable or discover twice")
    func startIsIdempotent() {
        let host = FakeDiscoveryHost(monitorsBackgroundEvents: false)
        let source = GameControllerEventSource(host: host)

        source.start { _ in }
        source.start { _ in }
        source.stop()

        // Duplicate observers or a second discovery call would show up here.
        #expect(
            host.operations == [
                .setMonitorsBackgroundEvents(true),
                .startDiscovery,
                .stopDiscovery,
                .setMonitorsBackgroundEvents(false),
            ]
        )
        #expect(!host.monitorsBackgroundEvents)
    }

    @Test("repeated start and stop cycles restore the original value each time")
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
}
