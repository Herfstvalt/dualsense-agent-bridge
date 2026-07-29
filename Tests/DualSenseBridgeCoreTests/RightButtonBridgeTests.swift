import Foundation
import Testing

@testable import DualSenseBridgeCore

@Suite("R2 holds the right mouse button and the right stick drags with it")
struct RightButtonBridgeTests {
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
        let pointer: RecordingPointerSink
        let keys: RecordingKeyboardSink
        var input = FakeControllerInput()
        var now = 100.0

        mutating func tick(_ count: Int = 1) {
            for _ in 0..<count {
                now += 0.01
                bridge.tick(at: now)
            }
        }
    }

    private func makeHarness(
        status: AccessibilityStatus = .granted,
        bindings: [ControllerControl: ControllerBinding] = ControllerProfile.starterTerminal.bindings,
        log: ((String) -> Void)? = nil
    ) -> Harness {
        let pointerSink = RecordingPointerSink()
        let keys = RecordingKeyboardSink()
        let bridge = ControllerBridge(
            profile: ControllerProfile(
                name: "test",
                bindings: bindings,
                navigation: Self.settings
            ),
            keyboard: SyntheticKeyboard(sink: keys, accessibility: .fixed(status)),
            pointer: SyntheticPointer(sink: pointerSink, accessibility: .fixed(status)),
            log: log
        )
        var harness = Harness(bridge: bridge, pointer: pointerSink, keys: keys)
        // Establish the tick baseline exactly as a running loop would.
        harness.tick()
        return harness
    }

    @Test("R2 presses the right mouse button and releasing R2 lifts it")
    func r2HoldsTheRightButton() {
        var harness = makeHarness()

        harness.bridge.handle(.connected(harness.input.controller))
        harness.bridge.handle(harness.input.press(.r2))
        harness.bridge.handle(harness.input.release(.r2))

        #expect(harness.pointer.transcript == ["right button down", "right button up"])
    }

    @Test("the right stick drags while the right button is held")
    func rightStickDragsWhileHeld() {
        var harness = makeHarness()

        harness.bridge.handle(harness.input.press(.r2))
        harness.bridge.handle(harness.input.stick(.right, x: 1, y: 0))
        harness.tick(2)

        #expect(
            harness.pointer.transcript == [
                "right button down",
                "drag dx=+1 dy=+0",
                "drag dx=+1 dy=+0",
            ]
        )
    }

    @Test("the right stick is an ordinary move once the button comes back up")
    func rightStickMovesWhenNotHeld() {
        var harness = makeHarness()

        harness.bridge.handle(harness.input.stick(.right, x: 1, y: 0))
        harness.tick()
        harness.bridge.handle(harness.input.press(.r2))
        harness.tick()
        harness.bridge.handle(harness.input.release(.r2))
        harness.tick()

        #expect(
            harness.pointer.transcript == [
                "move dx=+1 dy=+0",
                "right button down",
                "drag dx=+1 dy=+0",
                "right button up",
                "move dx=+1 dy=+0",
            ]
        )
    }

    // MARK: - Idempotence

    @Test("duplicate R2 presses and releases emit one down and one up")
    func duplicateTransitionsAreIdempotent() {
        var harness = makeHarness()

        harness.bridge.handle(harness.input.press(.r2))
        harness.bridge.handle(harness.input.press(.r2))
        harness.bridge.handle(harness.input.release(.r2))
        harness.bridge.handle(harness.input.release(.r2))

        #expect(harness.pointer.transcript == ["right button down", "right button up"])
    }

    @Test("an R2 release with no press behind it emits nothing")
    func outOfOrderReleaseEmitsNothing() {
        var harness = makeHarness()

        harness.bridge.handle(harness.input.release(.r2))

        #expect(harness.pointer.emissions.isEmpty)
    }

    @Test("R2 is not reported as an unmapped keyboard action and sends no keys")
    func r2IsNotAnUnmappedKeyboardAction() {
        var harness = makeHarness()

        let pressSteps = harness.bridge.handle(harness.input.press(.r2))
        let releaseSteps = harness.bridge.handle(harness.input.release(.r2))

        // R2 is spoken for by the pointer, so shrugging at it would teach the
        // user the control is unbound while it is in fact doing something.
        #expect(pressSteps.isEmpty)
        #expect(releaseSteps.isEmpty)
        #expect(harness.keys.emissions.isEmpty)
    }

    @Test("a profile that deliberately binds R2 still gets its keystroke")
    func anExplicitR2BindingIsStillHonored() {
        var bindings = ControllerProfile.starterTerminal.bindings
        bindings[.r2] = .tap(KeyStroke(key: .a))
        var harness = makeHarness(bindings: bindings)

        let steps = harness.bridge.handle(harness.input.press(.r2))

        // Only the shrug is suppressed, never a binding a user wrote on purpose.
        #expect(steps == [BridgeStep(action: .tap(KeyStroke(key: .a)), outcome: .emitted)])
        #expect(harness.pointer.transcript == ["right button down"])
    }

    // MARK: - Ownership

    @Test("one controller's R2 release cannot lift another controller's hold")
    func holdOwnershipIsPerController() {
        var harness = makeHarness()
        var second = FakeControllerInput(id: "fake-2", displayName: "Second DualSense")

        harness.bridge.handle(harness.input.press(.r2))
        harness.bridge.handle(second.press(.r2))
        // The second controller lets go, but the first is still holding R2 down.
        harness.bridge.handle(second.release(.r2))

        #expect(harness.pointer.transcript == ["right button down"])

        harness.bridge.handle(harness.input.release(.r2))
        #expect(harness.pointer.transcript == ["right button down", "right button up"])
    }

    @Test("a disconnect ends only the leaving controller's hold")
    func disconnectEndsOnlyTheLeavingHold() {
        var harness = makeHarness()
        var second = FakeControllerInput(id: "fake-2", displayName: "Second DualSense")

        harness.bridge.handle(.connected(harness.input.controller))
        harness.bridge.handle(.connected(second.controller))
        harness.bridge.handle(harness.input.press(.r2))
        harness.bridge.handle(second.press(.r2))
        harness.bridge.handle(.disconnected(second.controller))

        #expect(harness.pointer.transcript == ["right button down"])

        harness.bridge.handle(.disconnected(harness.input.controller))
        #expect(harness.pointer.transcript == ["right button down", "right button up"])
    }

    @Test("a disconnect releases the leaving controller's held right button")
    func disconnectReleasesTheHeldButton() {
        var harness = makeHarness()

        harness.bridge.handle(.connected(harness.input.controller))
        harness.bridge.handle(harness.input.press(.r2))
        harness.bridge.handle(.disconnected(harness.input.controller))

        #expect(harness.pointer.transcript == ["right button down", "right button up"])
    }

    @Test("a reconnect cannot inherit a hold from a previous session")
    func reconnectInheritsNothing() {
        var harness = makeHarness()

        harness.bridge.handle(harness.input.press(.r2))
        harness.bridge.handle(.connected(harness.input.controller))

        #expect(harness.pointer.transcript == ["right button down", "right button up"])

        // And the stick is back to plain movement, not a phantom drag.
        harness.bridge.handle(harness.input.stick(.right, x: 1, y: 0))
        harness.tick()
        #expect(harness.pointer.transcript.last == "move dx=+1 dy=+0")
    }

    // MARK: - Cleanup

    @Test("shutdown releases a held right button")
    func shutdownReleasesTheHeldButton() {
        var harness = makeHarness()

        harness.bridge.handle(harness.input.press(.r2))
        harness.bridge.shutdown()

        #expect(harness.pointer.transcript == ["right button down", "right button up"])
    }

    @Test("replacing the profile releases a held right button")
    func profileReplacementReleasesTheHeldButton() {
        var harness = makeHarness()

        harness.bridge.handle(harness.input.press(.r2))
        harness.bridge.use(profile: ControllerProfile(name: "other", bindings: [:], navigation: Self.settings))

        #expect(harness.pointer.transcript == ["right button down", "right button up"])
    }

    @Test("a replaced profile can hold the right button again afterwards")
    func rightButtonWorksAfterProfileReplacement() {
        var harness = makeHarness()

        harness.bridge.handle(harness.input.press(.r2))
        harness.bridge.use(profile: ControllerProfile(name: "other", bindings: [:], navigation: Self.settings))
        harness.bridge.handle(harness.input.press(.r2))

        // The sweep cleared the owner set, so this is a genuine fresh press.
        #expect(
            harness.pointer.transcript == [
                "right button down",
                "right button up",
                "right button down",
            ]
        )
    }

    @Test("deinit is a last-resort release for a caller that forgot to shut down")
    func deinitReleasesTheHeldButton() {
        let pointerSink = RecordingPointerSink()
        var input = FakeControllerInput()

        do {
            let bridge = ControllerBridge(
                profile: ControllerProfile(name: "test", bindings: [:], navigation: Self.settings),
                keyboard: SyntheticKeyboard(sink: RecordingKeyboardSink(), accessibility: .fixed(.granted)),
                pointer: SyntheticPointer(sink: pointerSink, accessibility: .fixed(.granted))
            )
            bridge.handle(input.press(.r2))
            #expect(pointerSink.transcript == ["right button down"])
        }

        #expect(pointerSink.transcript == ["right button down", "right button up"])
    }

    @Test("a revoked permission cannot latch the button through shutdown")
    func shutdownReleasesEvenAfterPermissionIsRevoked() {
        let accessibility = MutableAccessibility(.granted)
        let pointerSink = RecordingPointerSink()
        var input = FakeControllerInput()
        let bridge = ControllerBridge(
            profile: ControllerProfile(name: "test", bindings: [:], navigation: Self.settings),
            keyboard: SyntheticKeyboard(sink: RecordingKeyboardSink(), accessibility: accessibility.capability),
            pointer: SyntheticPointer(sink: pointerSink, accessibility: accessibility.capability)
        )

        bridge.handle(input.press(.r2))
        accessibility.revoke()
        bridge.shutdown()

        #expect(pointerSink.transcript == ["right button down", "right button up"])
    }

    @Test("a press is refused without permission and holds nothing")
    func pressRefusedWithoutPermission() {
        var harness = makeHarness(status: .denied)

        harness.bridge.handle(harness.input.press(.r2))
        harness.bridge.handle(harness.input.stick(.right, x: 1, y: 0))
        harness.tick()

        #expect(harness.pointer.emissions.isEmpty)
    }

    // MARK: - Diagnostics

    @Test("the log names the right-button transitions plainly enough to smoke test")
    func logNamesButtonTransitions() {
        let lines = LineCollector()
        var harness = makeHarness(log: { lines.append($0) })

        harness.bridge.handle(harness.input.press(.r2))
        harness.bridge.handle(harness.input.release(.r2))

        #expect(
            lines.lines == [
                "r2 pressed: pressRightButton -> emitted",
                "r2 released: releaseRightButton -> emitted",
            ]
        )
    }

    @Test("a dry run reports the button and the drag without touching the pointer")
    func dryRunReportsButtonAndDrag() {
        let lines = LineCollector()
        let sink = LoggingPointerSink(interval: 0, now: { 0 }, log: { lines.append($0) })
        let pointer = SyntheticPointer(sink: sink, accessibility: .fixed(.granted))

        pointer.perform(.pressRightButton)
        pointer.perform(.moveCursor(dx: 4, dy: 0))
        sink.flush()
        pointer.perform(.releaseRightButton)

        #expect(lines.lines.first == "right button down")
        #expect(lines.lines.contains { $0.contains("drag") })
        #expect(lines.lines.last == "right button up")
    }
}
