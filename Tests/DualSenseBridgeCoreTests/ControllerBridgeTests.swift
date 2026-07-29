import Testing

@testable import DualSenseBridgeCore

@Suite("a fake controller drives real keyboard intent end to end")
struct ControllerBridgeTests {
    private let wisprDown: [KeyEmission] = [.down(.control), .down(.option), .down(.space)]
    private let wisprUp: [KeyEmission] = [.up(.space), .up(.option), .up(.control)]

    private func makeBridge(
        profile: ControllerProfile = .starterTerminal,
        status: AccessibilityStatus = .granted
    ) -> (ControllerBridge, RecordingKeyboardSink) {
        let sink = RecordingKeyboardSink()
        let bridge = ControllerBridge(
            profile: profile,
            keyboard: SyntheticKeyboard(sink: sink, accessibility: .fixed(status))
        )
        return (bridge, sink)
    }

    @Test("hold to dictate, release, then send with Cross")
    func dictateThenSend() {
        var input = FakeControllerInput()
        let (bridge, sink) = makeBridge()

        bridge.handle(.connected(input.controller))
        bridge.handle(input.press(.l2))
        #expect(sink.emissions == wisprDown)

        bridge.handle(input.release(.l2))
        bridge.handle(input.press(.cross))
        bridge.handle(input.release(.cross))

        #expect(sink.emissions == wisprDown + wisprUp + [.down(.return), .up(.return)])
        #expect(bridge.heldKeys.isEmpty)
    }

    @Test("Circle cancels and R3 interrupts")
    func cancelAndInterrupt() {
        var input = FakeControllerInput()
        let (bridge, sink) = makeBridge()

        bridge.handle(input.press(.circle))
        bridge.handle(input.press(.r3))

        #expect(
            sink.emissions == [
                .down(.escape), .up(.escape),
                .down(.control), .down(.c), .up(.c), .up(.control),
            ]
        )
    }

    @Test("a disconnect during dictation releases the Wispr chord")
    func disconnectDuringDictation() {
        var input = FakeControllerInput()
        let (bridge, sink) = makeBridge()

        bridge.handle(.connected(input.controller))
        bridge.handle(input.press(.l2))
        sink.reset()

        bridge.handle(.disconnected(input.controller))

        #expect(sink.emissions == wisprUp)
        #expect(bridge.heldKeys.isEmpty)
        #expect(bridge.connectedControllers.isEmpty)
    }

    @Test("shutdown during dictation releases the Wispr chord")
    func shutdownDuringDictation() {
        var input = FakeControllerInput()
        let (bridge, sink) = makeBridge()

        bridge.handle(input.press(.l2))
        sink.reset()

        bridge.shutdown()

        #expect(sink.emissions == wisprUp)
        #expect(bridge.heldKeys.isEmpty)
    }

    @Test("shutdown is idempotent")
    func shutdownIsIdempotent() {
        var input = FakeControllerInput()
        let (bridge, sink) = makeBridge()

        bridge.handle(input.press(.l2))
        bridge.shutdown()
        sink.reset()
        bridge.shutdown()

        #expect(sink.emissions.isEmpty)
        #expect(bridge.heldKeys.isEmpty)
    }

    @Test("input after shutdown is ignored so no key can be left down")
    func inputAfterShutdownIsIgnored() {
        var input = FakeControllerInput()
        let (bridge, sink) = makeBridge()

        bridge.shutdown()
        sink.reset()
        bridge.handle(input.press(.l2))
        bridge.handle(input.press(.cross))

        #expect(sink.emissions.isEmpty)
        #expect(bridge.heldKeys.isEmpty)
    }

    @Test("duplicate and out-of-order hold events leave nothing held")
    func duplicateAndOutOfOrderEvents() {
        var input = FakeControllerInput()
        let (bridge, sink) = makeBridge()

        bridge.handle(input.release(.l2))
        bridge.handle(input.press(.l2))
        bridge.handle(input.press(.l2))
        bridge.handle(input.release(.l2))
        bridge.handle(input.release(.l2))

        #expect(sink.emissions == wisprDown + wisprUp)
        #expect(bridge.heldKeys.isEmpty)
    }

    @Test("two connected controllers are tracked independently")
    func multipleControllers() {
        var first = FakeControllerInput(id: "fake-1")
        var second = FakeControllerInput(id: "fake-2", displayName: "Second DualSense")
        let (bridge, sink) = makeBridge()

        bridge.handle(.connected(first.controller))
        bridge.handle(.connected(second.controller))
        #expect(bridge.connectedControllers.count == 2)

        bridge.handle(first.press(.l2))
        bridge.handle(second.press(.l2))
        sink.reset()

        bridge.handle(.disconnected(second.controller))
        #expect(bridge.connectedControllers.map(\.id) == ["fake-1"])
        #expect(bridge.heldKeys.isEmpty, "the surviving hold is swept too, which is the safe choice")
        #expect(sink.emissions == wisprUp)
    }

    @Test("without permission nothing is emitted and the refusal is reported")
    func refusesWithoutPermission() {
        var input = FakeControllerInput()
        let (bridge, sink) = makeBridge(status: .denied)

        let steps = bridge.handle(input.press(.cross))

        #expect(sink.emissions.isEmpty)
        #expect(steps.count == 1)
        #expect(steps[0].outcome.isRefusal)
        #expect(!bridge.diagnostics.accessibility.isUsable)
    }

    @Test("steps pair each routed action with its keyboard outcome")
    func stepsPairActionAndOutcome() {
        var input = FakeControllerInput()
        let (bridge, _) = makeBridge()

        let steps = bridge.handle(input.press(.micButton))

        #expect(steps == [BridgeStep(action: .unmapped(.micButton), outcome: .noOutput)])
        #expect(steps[0].description == "unmapped(micButton) -> no output")
    }

    @Test("a log line is produced for every handled input")
    func logsEveryInput() {
        var input = FakeControllerInput()
        let sink = RecordingKeyboardSink()
        nonisolated(unsafe) var lines: [String] = []
        let bridge = ControllerBridge(
            profile: .starterTerminal,
            keyboard: SyntheticKeyboard(sink: sink, accessibility: .fixed(.granted)),
            log: { lines.append($0) }
        )

        bridge.handle(.connected(input.controller))
        bridge.handle(input.press(.l2))
        bridge.handle(input.release(.l2))
        bridge.shutdown()

        #expect(lines.contains("connected Fake DualSense (fake-1)"))
        #expect(lines.contains("l2 pressed: beginHold(control+option+space) -> emitted"))
        #expect(lines.contains("l2 released: endHold(control+option+space) -> emitted"))
        #expect(lines.contains("shutdown"))
        #expect(!lines.contains(where: { $0.contains("/Users/") }))
    }

    @Test("diagnostics summarize profile, controllers, held keys, and permission")
    func diagnosticsSnapshot() {
        var input = FakeControllerInput()
        let (bridge, _) = makeBridge()

        bridge.handle(.connected(input.controller))
        bridge.handle(input.press(.l2))

        let diagnostics = bridge.diagnostics
        #expect(diagnostics.profileName == "starter-terminal")
        #expect(diagnostics.connectedControllers == [input.controller])
        #expect(diagnostics.heldKeys == ["control", "option", "space"])
        #expect(diagnostics.accessibility.isUsable)
        #expect(diagnostics.bindingSummary.contains("cross -> tap return"))
        #expect(diagnostics.text.contains("Profile: starter-terminal"))
        #expect(diagnostics.text.contains("Held keys: control, option, space"))
    }

    @Test("swapping profiles mid-session releases the previous hold")
    func swappingProfilesReleasesHolds() throws {
        var input = FakeControllerInput()
        let (bridge, sink) = makeBridge()
        let custom = ControllerProfile(
            name: "custom",
            bindings: [.r1: .hold(try KeyStroke(parsing: "cmd+shift+d"))]
        )

        bridge.handle(input.press(.l2))
        sink.reset()
        bridge.use(profile: custom)

        #expect(sink.emissions == wisprUp)
        #expect(bridge.diagnostics.profileName == "custom")

        bridge.handle(input.press(.r1))
        #expect(sink.emissions.suffix(3) == [.down(.shift), .down(.command), .down(.d)])
        bridge.shutdown()
        #expect(bridge.heldKeys.isEmpty)
    }
}
