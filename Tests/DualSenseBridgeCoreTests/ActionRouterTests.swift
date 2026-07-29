import Testing

@testable import DualSenseBridgeCore

/// Builds normalized events without a controller or an input framework.
struct FakeControllerInput {
    let controller: ControllerIdentity
    private var clock: Double = 0

    init(id: String = "fake-1", displayName: String = "Fake DualSense") {
        controller = ControllerIdentity(id: id, displayName: displayName)
    }

    mutating func press(_ control: ControllerControl) -> ControllerInput {
        event(control, .pressed)
    }

    mutating func release(_ control: ControllerControl) -> ControllerInput {
        event(control, .released)
    }

    /// A thumbstick resting at a normalized position, with `y` positive up
    /// exactly as a gamepad reports it.
    mutating func stick(_ stick: ControllerStick, x: Double, y: Double) -> ControllerInput {
        clock += 0.01
        return .axis(
            ControllerAxisEvent(
                controller: controller,
                stick: stick,
                position: StickVector(x: x, y: y),
                timestamp: clock,
                source: .fake
            )
        )
    }

    mutating func event(_ control: ControllerControl, _ phase: ControllerEventPhase) -> ControllerInput {
        clock += 0.01
        return .button(
            ControllerEvent(
                controller: controller,
                control: control,
                phase: phase,
                timestamp: clock,
                source: .fake
            )
        )
    }
}

@Suite("the action router maps controller input to keyboard intent")
struct ActionRouterTests {
    private let wispr = KeyStroke(key: .space, modifiers: [.control, .option])

    @Test("Cross taps Return")
    func crossTapsReturn() {
        var input = FakeControllerInput()
        var router = ActionRouter(profile: .starterTerminal)

        #expect(router.handle(input.press(.cross)) == [.tap(KeyStroke(key: .return))])
    }

    @Test("Circle taps Escape and R3 taps the Wispr Flow toggle")
    func circleAndDictationToggle() {
        var input = FakeControllerInput()
        var router = ActionRouter(profile: .starterTerminal)

        #expect(router.handle(input.press(.circle)) == [.tap(KeyStroke(key: .escape))])
        #expect(router.handle(input.press(.r3)) == [.tap(KeyStroke(key: .s, modifiers: .control))])
    }

    @Test("the shoulders send the tmux prefix and then a command key")
    func shouldersSendTmuxSequences() {
        var input = FakeControllerInput()
        var router = ActionRouter(profile: .starterTerminal)
        let prefix = KeyStroke(key: .b, modifiers: .control)

        #expect(router.handle(input.press(.r1)) == [.tap(prefix), .tap(KeyStroke(key: .n))])
        #expect(router.handle(input.press(.l1)) == [.tap(prefix), .tap(KeyStroke(key: .p))])
        #expect(router.handle(input.press(.l3)) == [.tap(prefix), .tap(KeyStroke(key: .s))])
    }

    @Test("the D-pad walks history and the touchpad click toggles the terminal")
    func dpadAndTouchpad() {
        var input = FakeControllerInput()
        var router = ActionRouter(profile: .starterTerminal)

        #expect(router.handle(input.press(.dpadUp)) == [.tap(KeyStroke(key: .arrowUp))])
        #expect(router.handle(input.press(.dpadDown)) == [.tap(KeyStroke(key: .arrowDown))])
        #expect(
            router.handle(input.press(.touchpadButton))
                == [.tap(KeyStroke(key: .grave, modifiers: .control))]
        )
    }

    @Test("a tap binding emits nothing on release")
    func tapIgnoresRelease() {
        var input = FakeControllerInput()
        var router = ActionRouter(profile: .starterTerminal)

        _ = router.handle(input.press(.cross))
        #expect(router.handle(input.release(.cross)).isEmpty)
    }

    @Test("the hold control begins and ends the Wispr shortcut")
    func holdBeginsAndEnds() {
        var input = FakeControllerInput()
        var router = ActionRouter(profile: .starterTerminal)

        #expect(router.handle(input.press(.l2)) == [.beginHold(wispr)])
        #expect(router.handle(input.release(.l2)) == [.endHold(wispr)])
        #expect(router.heldControlCount == 0)
    }

    @Test("a repeated press while already holding does not re-emit the shortcut")
    func duplicatePressIsIdempotent() {
        var input = FakeControllerInput()
        var router = ActionRouter(profile: .starterTerminal)

        #expect(router.handle(input.press(.l2)) == [.beginHold(wispr)])
        #expect(router.handle(input.press(.l2)).isEmpty)
        #expect(router.heldControlCount == 1)
        #expect(router.handle(input.release(.l2)) == [.endHold(wispr)])
    }

    @Test("a release without a matching press is harmless")
    func unmatchedReleaseIsHarmless() {
        var input = FakeControllerInput()
        var router = ActionRouter(profile: .starterTerminal)

        #expect(router.handle(input.release(.l2)).isEmpty)
        #expect(router.handle(input.release(.l2)).isEmpty)
        #expect(router.heldControlCount == 0)
    }

    @Test("a duplicate release after a completed hold is harmless")
    func duplicateReleaseIsHarmless() {
        var input = FakeControllerInput()
        var router = ActionRouter(profile: .starterTerminal)

        _ = router.handle(input.press(.l2))
        #expect(router.handle(input.release(.l2)) == [.endHold(wispr)])
        #expect(router.handle(input.release(.l2)).isEmpty)
    }

    @Test("out-of-order release then press still ends in a clean state")
    func outOfOrderSequence() {
        var input = FakeControllerInput()
        var router = ActionRouter(profile: .starterTerminal)

        let actions = [
            router.handle(input.release(.l2)),
            router.handle(input.press(.l2)),
            router.handle(input.press(.l2)),
            router.handle(input.release(.l2)),
            router.handle(input.release(.l2)),
        ].flatMap { $0 }

        #expect(actions == [.beginHold(wispr), .endHold(wispr)])
        #expect(router.heldControlCount == 0)
    }

    @Test("an unmapped control is reported for diagnostics without keyboard output")
    func unmappedControlIsReported() {
        var input = FakeControllerInput()
        var router = ActionRouter(profile: .starterTerminal)

        #expect(router.handle(input.press(.micButton)) == [.unmapped(.micButton)])
        #expect(router.handle(input.release(.micButton)).isEmpty)
    }

    @Test("disconnect releases the hold that controller was holding")
    func disconnectReleasesHeldShortcut() {
        var input = FakeControllerInput()
        var router = ActionRouter(profile: .starterTerminal)

        _ = router.handle(input.press(.l2))
        #expect(router.handle(.disconnected(input.controller)) == [.endHold(wispr), .releaseAllHeldKeys])
        #expect(router.heldControlCount == 0)
    }

    @Test("disconnect with nothing held still sweeps the keyboard clean")
    func disconnectAlwaysSweeps() {
        var router = ActionRouter(profile: .starterTerminal)
        let controller = ControllerIdentity(id: "fake-1", displayName: "Fake DualSense")

        #expect(router.handle(.disconnected(controller)) == [.releaseAllHeldKeys])
    }

    @Test("the disconnected controller's holds are ended first, then the rest")
    func disconnectEndsTheLeavingControllerFirst() {
        var first = FakeControllerInput(id: "fake-1")
        var second = FakeControllerInput(id: "fake-2")
        var router = ActionRouter(profile: .starterTerminal)

        _ = router.handle(first.press(.cross))
        _ = router.handle(second.press(.l2))
        _ = router.handle(first.press(.l2))
        #expect(router.heldControlCount == 2)

        let actions = router.handle(.disconnected(first.controller))

        // Every hold is ended because the sweep releases every physical key;
        // leaving a surviving hold recorded would desynchronize the router from
        // the keyboard.
        #expect(actions == [.endHold(wispr), .endHold(wispr), .releaseAllHeldKeys])
        #expect(router.heldControlCount == 0)
    }

    @Test("a surviving controller can press again after another one disconnects")
    func survivingControllerCanPressAgain() {
        var first = FakeControllerInput(id: "fake-1")
        var second = FakeControllerInput(id: "fake-2")
        var router = ActionRouter(profile: .starterTerminal)

        _ = router.handle(first.press(.l2))
        _ = router.handle(second.press(.l2))
        _ = router.handle(.disconnected(first.controller))

        // The stale release is harmless, and the next press starts a fresh hold
        // rather than being swallowed as a duplicate.
        #expect(router.handle(second.release(.l2)).isEmpty)
        #expect(router.handle(second.press(.l2)) == [.beginHold(wispr)])
        #expect(router.handle(second.release(.l2)) == [.endHold(wispr)])
        #expect(router.heldControlCount == 0)
    }

    @Test("a controller that represses without releasing after a sweep still works")
    func repressWithoutReleaseAfterSweep() {
        var first = FakeControllerInput(id: "fake-1")
        var second = FakeControllerInput(id: "fake-2")
        var router = ActionRouter(profile: .starterTerminal)

        _ = router.handle(second.press(.l2))
        _ = router.handle(first.press(.cross))
        _ = router.handle(.disconnected(first.controller))

        #expect(router.handle(second.press(.l2)) == [.beginHold(wispr)])
        #expect(router.heldControlCount == 1)
    }

    @Test("two controls bound to the same shortcut are tracked separately")
    func twoControlsSharingOneShortcut() throws {
        var input = FakeControllerInput()
        let shared = try KeyStroke(parsing: "control+option+space")
        var router = ActionRouter(
            profile: ControllerProfile(
                name: "shared",
                bindings: [.l2: .hold(shared), .r2: .hold(shared)]
            )
        )

        #expect(router.handle(input.press(.l2)) == [.beginHold(shared)])
        #expect(router.handle(input.press(.r2)) == [.beginHold(shared)])
        #expect(router.heldControlCount == 2)

        #expect(router.handle(input.release(.l2)) == [.endHold(shared)])
        #expect(router.handle(input.release(.r2)) == [.endHold(shared)])
        #expect(router.heldControlCount == 0)
    }

    @Test("shutdown releases every hold across controllers")
    func shutdownReleasesEverything() {
        var first = FakeControllerInput(id: "fake-1")
        var second = FakeControllerInput(id: "fake-2")
        var router = ActionRouter(profile: .starterTerminal)

        _ = router.handle(first.press(.l2))
        _ = router.handle(second.press(.l2))

        let actions = router.handle(.shutdown)
        #expect(actions.filter { $0 == .endHold(wispr) }.count == 2)
        #expect(actions.last == .releaseAllHeldKeys)
        #expect(router.heldControlCount == 0)
    }

    @Test("connect clears any stale hold recorded for that controller")
    func connectClearsStaleHolds() {
        var input = FakeControllerInput()
        var router = ActionRouter(profile: .starterTerminal)

        _ = router.handle(input.press(.l2))
        #expect(router.handle(.connected(input.controller)) == [.endHold(wispr)])
        #expect(router.heldControlCount == 0)
    }

    @Test("routing is a pure function of the input sequence")
    func routingIsDeterministic() {
        func run() -> [BridgeAction] {
            var input = FakeControllerInput()
            var router = ActionRouter(profile: .starterTerminal)
            return [
                router.handle(input.press(.l2)),
                router.handle(input.press(.cross)),
                router.handle(input.release(.l2)),
                router.handle(.shutdown),
            ].flatMap { $0 }
        }

        #expect(run() == run())
        #expect(
            run() == [
                .beginHold(wispr),
                .tap(KeyStroke(key: .return)),
                .endHold(wispr),
                .releaseAllHeldKeys,
            ]
        )
    }

    @Test("a replaced profile changes later routing without restarting")
    func profileCanBeReplaced() throws {
        var input = FakeControllerInput()
        var router = ActionRouter(profile: .starterTerminal)
        let custom = ControllerProfile(
            name: "custom",
            bindings: [.r1: .hold(try KeyStroke(parsing: "cmd+shift+d"))]
        )

        _ = router.handle(input.press(.l2))
        let actions = router.replaceProfile(with: custom)

        #expect(actions == [.endHold(wispr), .releaseAllHeldKeys])
        #expect(router.handle(input.press(.l2)) == [.unmapped(.l2)])
        #expect(router.handle(input.press(.r1)) == [.beginHold(KeyStroke(key: .d, modifiers: [.command, .shift]))])
    }
}
