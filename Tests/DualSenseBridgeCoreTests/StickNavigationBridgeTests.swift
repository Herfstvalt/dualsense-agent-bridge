import Foundation
import Testing

@testable import DualSenseBridgeCore

@Suite("a fake stick drives real pointer motion end to end")
struct StickNavigationBridgeTests {
    /// Linear response, 100 units per second, so a 0.01s tick is exactly one
    /// pixel at full deflection.
    private static let settings = NavigationSettings(
        pointer: NavigationAxisSettings(deadzone: 0.2, responseExponent: 1, speed: 100),
        scroll: NavigationAxisSettings(deadzone: 0.2, responseExponent: 1, speed: 100),
        tickInterval: 0.01,
        maximumTickInterval: 0.05
    )

    private struct Harness {
        let bridge: ControllerBridge
        let keys: RecordingKeyboardSink
        let pointer: RecordingPointerSink
        var input = FakeControllerInput()
        var now = 100.0

        /// Advances the clock and ticks, mirroring the CLI run loop.
        @discardableResult
        mutating func tick(_ count: Int = 1) -> [NavigationStep] {
            var steps: [NavigationStep] = []
            for _ in 0..<count {
                now += 0.01
                steps.append(contentsOf: bridge.tick(at: now))
            }
            return steps
        }
    }

    private func makeHarness(
        status: AccessibilityStatus = .granted,
        log: ((String) -> Void)? = nil
    ) -> Harness {
        let keys = RecordingKeyboardSink()
        let pointerSink = RecordingPointerSink()
        let profile = ControllerProfile(
            name: "test",
            bindings: ControllerProfile.starterTerminal.bindings,
            navigation: Self.settings
        )
        let bridge = ControllerBridge(
            profile: profile,
            keyboard: SyntheticKeyboard(sink: keys, accessibility: .fixed(status)),
            pointer: SyntheticPointer(sink: pointerSink, accessibility: .fixed(status)),
            log: log
        )
        var harness = Harness(bridge: bridge, keys: keys, pointer: pointerSink)
        // Establish the tick baseline exactly as a running loop would.
        harness.tick()
        return harness
    }

    // MARK: - Continuous motion

    @Test("holding the right stick keeps moving the cursor with no further events")
    func heldRightStickKeepsMovingTheCursor() {
        var harness = makeHarness()
        harness.bridge.handle(.connected(harness.input.controller))

        harness.bridge.handle(harness.input.stick(.right, x: 1, y: 0))
        harness.tick(3)

        #expect(harness.pointer.emissions == [.move(dx: 1, dy: 0), .move(dx: 1, dy: 0), .move(dx: 1, dy: 0)])
    }

    @Test("holding the left stick scrolls instead of moving the cursor")
    func heldLeftStickScrolls() {
        var harness = makeHarness()

        harness.bridge.handle(harness.input.stick(.left, x: 0, y: 1))
        harness.tick(2)

        #expect(harness.pointer.emissions == [.scroll(dx: 0, dy: 1), .scroll(dx: 0, dy: 1)])
    }

    @Test("an axis event alone emits nothing until the next tick")
    func axisEventsAreTickDriven() {
        var harness = makeHarness()

        let steps = harness.bridge.handle(harness.input.stick(.right, x: 1, y: 0))

        #expect(steps.isEmpty)
        #expect(harness.pointer.emissions.isEmpty)
    }

    @Test("a stick resting inside the deadzone never moves the cursor")
    func restingStickIsIgnored() {
        var harness = makeHarness()

        harness.bridge.handle(harness.input.stick(.right, x: 0.1, y: -0.05))
        harness.tick(10)

        #expect(harness.pointer.emissions.isEmpty)
    }

    // MARK: - Release

    @Test("releasing the stick stops motion on the very next tick")
    func releaseStopsMotion() {
        var harness = makeHarness()

        harness.bridge.handle(harness.input.stick(.right, x: 1, y: 0))
        harness.tick(2)
        harness.pointer.reset()

        harness.bridge.handle(harness.input.stick(.right, x: 0, y: 0))
        harness.tick(5)

        #expect(harness.pointer.emissions.isEmpty)
    }

    // MARK: - Coexistence with button actions

    @Test("stick motion and button actions do not starve each other")
    func motionCoexistsWithButtons() {
        var harness = makeHarness()
        harness.bridge.handle(.connected(harness.input.controller))

        harness.bridge.handle(harness.input.stick(.right, x: 1, y: 0))
        harness.bridge.handle(harness.input.press(.l2))
        harness.tick(2)
        harness.bridge.handle(harness.input.press(.cross))
        harness.tick(2)
        harness.bridge.handle(harness.input.release(.l2))

        #expect(harness.pointer.emissions.count == 4)
        #expect(
            harness.keys.emissions == [
                .down(.control), .down(.option), .down(.space),
                .down(.return), .up(.return),
                .up(.space), .up(.option), .up(.control),
            ]
        )
    }

    @Test("a stick held during dictation does not disturb the held chord")
    func motionDoesNotReleaseHeldKeys() {
        var harness = makeHarness()

        harness.bridge.handle(harness.input.press(.l2))
        harness.bridge.handle(harness.input.stick(.left, x: 0, y: -1))
        harness.tick(3)

        #expect(harness.bridge.heldKeys == [.control, .option, .space])
        #expect(harness.pointer.emissions == [.scroll(dx: 0, dy: -1), .scroll(dx: 0, dy: -1), .scroll(dx: 0, dy: -1)])
    }

    // MARK: - Disconnect and shutdown

    @Test("a disconnect while the stick is held stops motion at once")
    func disconnectStopsMotion() {
        var harness = makeHarness()
        harness.bridge.handle(.connected(harness.input.controller))
        harness.bridge.handle(harness.input.stick(.right, x: 1, y: 1))
        harness.tick(2)
        harness.pointer.reset()

        harness.bridge.handle(.disconnected(harness.input.controller))
        harness.tick(5)

        #expect(harness.pointer.emissions.isEmpty)
        #expect(harness.bridge.isNavigating == false)
    }

    @Test("a reconnect cannot inherit motion from the previous session")
    func reconnectStartsStill() {
        var harness = makeHarness()
        harness.bridge.handle(.connected(harness.input.controller))
        harness.bridge.handle(harness.input.stick(.right, x: 1, y: 0))
        harness.tick()
        harness.pointer.reset()

        harness.bridge.handle(.connected(harness.input.controller))
        harness.tick(5)

        #expect(harness.pointer.emissions.isEmpty)
    }

    @Test("shutdown stops motion and later ticks do nothing")
    func shutdownStopsMotion() {
        var harness = makeHarness()
        harness.bridge.handle(harness.input.stick(.right, x: 1, y: 0))
        harness.tick(2)
        harness.pointer.reset()

        harness.bridge.shutdown()
        harness.tick(5)

        #expect(harness.pointer.emissions.isEmpty)
        #expect(!harness.bridge.isRunning)
    }

    @Test("a stick pushed after shutdown is ignored")
    func inputAfterShutdownIsIgnored() {
        var harness = makeHarness()
        harness.bridge.shutdown()

        harness.bridge.handle(harness.input.stick(.right, x: 1, y: 0))
        harness.tick(5)

        #expect(harness.pointer.emissions.isEmpty)
    }

    @Test("switching profiles stops motion so a new mapping cannot run away")
    func profileSwitchStopsMotion() {
        var harness = makeHarness()
        harness.bridge.handle(harness.input.stick(.right, x: 1, y: 0))
        harness.tick()
        harness.pointer.reset()

        var slower = Self.settings
        slower.pointer.speed = 50
        harness.bridge.use(
            profile: ControllerProfile(name: "slower", bindings: [:], navigation: slower)
        )
        harness.tick(3)

        #expect(harness.pointer.emissions.isEmpty)
        #expect(harness.bridge.diagnostics.navigationSummary.contains { $0.contains("50") })
    }

    // MARK: - Permission and logging

    @Test("motion is refused without Accessibility permission and logged once")
    func motionIsRefusedWithoutPermission() {
        let lines = LineCollector()
        var harness = makeHarness(status: .denied, log: { lines.append($0) })

        harness.bridge.handle(harness.input.stick(.right, x: 1, y: 0))
        harness.tick(20)

        #expect(harness.pointer.emissions.isEmpty)
        // One warning, not one per tick.
        #expect(lines.lines.filter { $0.contains("navigation") }.count == 1)
    }

    @Test("normal motion produces no per-tick log noise")
    func motionIsNotLoggedPerTick() {
        let lines = LineCollector()
        var harness = makeHarness(log: { lines.append($0) })

        harness.bridge.handle(harness.input.stick(.right, x: 1, y: 0))
        harness.tick(50)

        #expect(lines.lines.isEmpty)
    }

    @Test("diagnostics report the active navigation values")
    func diagnosticsReportNavigation() {
        let harness = makeHarness()
        let diagnostics = harness.bridge.diagnostics

        #expect(diagnostics.navigationSummary.contains { $0.hasPrefix("right stick -> pointer") })
        #expect(diagnostics.text.contains("Navigation:"))
        #expect(!diagnostics.text.contains("/Users"))
    }

    @Test("a bridge without a pointer boundary simply does not navigate")
    func navigationIsOptional() {
        var input = FakeControllerInput()
        let bridge = ControllerBridge(
            profile: .starterTerminal,
            keyboard: SyntheticKeyboard(sink: RecordingKeyboardSink(), accessibility: .fixed(.granted))
        )

        bridge.handle(input.stick(.right, x: 1, y: 0))

        #expect(bridge.tick(at: 1).isEmpty)
        #expect(bridge.tick(at: 2).isEmpty)
        #expect(bridge.diagnostics.navigationSummary.isEmpty == false)
    }

    @Test("a navigation step describes itself for diagnostics")
    func stepDescription() {
        let step = NavigationStep(
            output: .moveCursor(dx: 1, dy: 0),
            outcome: .emitted(dx: 1, dy: 0)
        )

        #expect(step.description == "moveCursor dx=+1.00 dy=+0.00 -> emitted dx=1 dy=0")
    }
}
