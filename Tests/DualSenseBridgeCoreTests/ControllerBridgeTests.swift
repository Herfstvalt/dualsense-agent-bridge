import Testing

@testable import DualSenseBridgeCore

@Suite("a fake controller drives real keyboard intent end to end")
struct ControllerBridgeTests {
    private let wisprDown: [KeyEmission] = [.down(.control), .down(.option), .down(.space)]
    private let wisprUp: [KeyEmission] = [.up(.space), .up(.option), .up(.control)]
    private static let wisprTestProfile: ControllerProfile = {
        var bindings = ControllerProfile.starterTerminal.bindings
        bindings[.micButton] = .hold(KeyStroke(key: .space, modifiers: [.control, .option]))
        return ControllerProfile(name: "starter-terminal", bindings: bindings)
    }()

    private func makeBridge(
        profile: ControllerProfile = Self.wisprTestProfile,
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
        bridge.handle(input.press(.micButton))
        #expect(sink.emissions == wisprDown)

        bridge.handle(input.release(.micButton))
        bridge.handle(input.press(.cross))
        bridge.handle(input.release(.cross))

        #expect(sink.emissions == wisprDown + wisprUp + [.down(.return), .up(.return)])
        #expect(bridge.heldKeys.isEmpty)
    }

    @Test("Circle cancels and R3 toggles dictation")
    func cancelAndDictationToggle() {
        var input = FakeControllerInput()
        let (bridge, sink) = makeBridge()

        bridge.handle(input.press(.circle))
        bridge.handle(input.press(.r3))
        bridge.handle(input.release(.r3))

        #expect(
            sink.emissions == [
                .down(.escape), .up(.escape),
                .down(.control), .down(.s), .up(.s), .up(.control),
            ]
        )
    }

    @Test("R1 sends the tmux prefix and the next-window key end to end")
    func tmuxNextWindowEndToEnd() {
        var input = FakeControllerInput()
        let (bridge, sink) = makeBridge()

        bridge.handle(input.press(.r1))

        #expect(
            sink.emissions == [
                .down(.control), .down(.b), .up(.b), .up(.control),
                .down(.n), .up(.n),
            ]
        )
        #expect(bridge.heldKeys.isEmpty)
    }

    @Test("D-pad Left toggles tmux pane zoom before the editing shortcuts")
    func editingShortcutsEndToEnd() {
        var input = FakeControllerInput()
        let (bridge, sink) = makeBridge()

        bridge.handle(input.press(.dpadLeft))
        bridge.handle(input.press(.dpadRight))
        bridge.handle(input.press(.options))

        #expect(
            sink.emissions == [
                .down(.control), .down(.b), .up(.b), .up(.control),
                .down(.z), .up(.z),
                .down(.command), .down(.c), .up(.c), .up(.command),
                .down(.command), .down(.v), .up(.v), .up(.command),
            ]
        )
        #expect(bridge.heldKeys.isEmpty)
    }

    @Test("a disconnect during dictation releases the Wispr chord")
    func disconnectDuringDictation() {
        var input = FakeControllerInput()
        let (bridge, sink) = makeBridge()

        bridge.handle(.connected(input.controller))
        bridge.handle(input.press(.micButton))
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

        bridge.handle(input.press(.micButton))
        sink.reset()

        bridge.shutdown()

        #expect(sink.emissions == wisprUp)
        #expect(bridge.heldKeys.isEmpty)
    }

    @Test("shutdown is idempotent")
    func shutdownIsIdempotent() {
        var input = FakeControllerInput()
        let (bridge, sink) = makeBridge()

        bridge.handle(input.press(.micButton))
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
        bridge.handle(input.press(.micButton))
        bridge.handle(input.press(.cross))

        #expect(sink.emissions.isEmpty)
        #expect(bridge.heldKeys.isEmpty)
    }

    @Test("duplicate and out-of-order hold events leave nothing held")
    func duplicateAndOutOfOrderEvents() {
        var input = FakeControllerInput()
        let (bridge, sink) = makeBridge()

        bridge.handle(input.release(.micButton))
        bridge.handle(input.press(.micButton))
        bridge.handle(input.press(.micButton))
        bridge.handle(input.release(.micButton))
        bridge.handle(input.release(.micButton))

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

        bridge.handle(first.press(.micButton))
        bridge.handle(second.press(.micButton))
        sink.reset()

        bridge.handle(.disconnected(second.controller))
        #expect(bridge.connectedControllers.map(\.id) == ["fake-1"])
        #expect(bridge.heldKeys.isEmpty, "the surviving hold is swept too, which is the safe choice")
        #expect(sink.emissions == wisprUp)
    }

    @Test("a surviving controller gets a fresh chord after another one disconnects")
    func survivorRepressesAfterDisconnect() {
        var first = FakeControllerInput(id: "fake-1")
        var second = FakeControllerInput(id: "fake-2", displayName: "Second DualSense")
        let (bridge, sink) = makeBridge()

        bridge.handle(.connected(first.controller))
        bridge.handle(.connected(second.controller))
        bridge.handle(first.press(.micButton))
        bridge.handle(second.press(.micButton))
        #expect(sink.emissions == wisprDown, "the chord is pressed once and shared")

        sink.reset()
        bridge.handle(.disconnected(first.controller))
        #expect(sink.emissions == wisprUp)
        #expect(bridge.heldKeys.isEmpty)

        // The survivor's stale release is harmless and the next press must
        // physically press the chord again rather than being swallowed.
        sink.reset()
        bridge.handle(second.release(.micButton))
        #expect(sink.emissions.isEmpty)

        bridge.handle(second.press(.micButton))
        #expect(sink.emissions == wisprDown)
        #expect(bridge.heldKeys == [.control, .option, .space])

        bridge.handle(second.release(.micButton))
        #expect(bridge.heldKeys.isEmpty)
    }

    @Test("two controls bound to the same shortcut release independently")
    func twoControlsSharingOneShortcut() throws {
        var input = FakeControllerInput()
        let shared = try KeyStroke(parsing: "control+option+space")
        let (bridge, sink) = makeBridge(
            profile: ControllerProfile(
                name: "shared",
                bindings: [.micButton: .hold(shared), .r2: .hold(shared)]
            )
        )

        bridge.handle(input.press(.micButton))
        bridge.handle(input.press(.r2))
        #expect(sink.emissions == wisprDown)

        sink.reset()
        bridge.handle(input.release(.micButton))
        #expect(sink.emissions.isEmpty, "the other control still holds the chord")
        #expect(bridge.heldKeys == [.control, .option, .space])

        bridge.handle(input.release(.r2))
        #expect(sink.emissions == wisprUp)
        #expect(bridge.heldKeys.isEmpty)
    }

    @Test("a disconnect releases the chord even if permission was revoked mid-hold")
    func disconnectReleasesAfterPermissionRevoked() {
        var input = FakeControllerInput()
        let sink = RecordingKeyboardSink()
        let permission = MutableAccessibility(.granted)
        let bridge = ControllerBridge(
            profile: Self.wisprTestProfile,
            keyboard: SyntheticKeyboard(sink: sink, accessibility: permission.capability)
        )

        bridge.handle(.connected(input.controller))
        bridge.handle(input.press(.micButton))
        permission.revoke()
        sink.reset()

        bridge.handle(.disconnected(input.controller))

        #expect(sink.emissions == wisprUp, "cleanup must never be refused")
        #expect(bridge.heldKeys.isEmpty)
    }

    @Test("shutdown releases the chord even if permission was revoked mid-hold")
    func shutdownReleasesAfterPermissionRevoked() {
        var input = FakeControllerInput()
        let sink = RecordingKeyboardSink()
        let permission = MutableAccessibility(.granted)
        let bridge = ControllerBridge(
            profile: Self.wisprTestProfile,
            keyboard: SyntheticKeyboard(sink: sink, accessibility: permission.capability)
        )

        bridge.handle(input.press(.micButton))
        permission.revoke()
        sink.reset()

        bridge.shutdown()

        #expect(sink.emissions == wisprUp)
        #expect(bridge.heldKeys.isEmpty)
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

        let steps = bridge.handle(input.press(.create))

        #expect(steps == [BridgeStep(action: .unmapped(.create), outcome: .noOutput)])
        #expect(steps[0].description == "unmapped(create) -> no output")
    }

    @Test("a log line is produced for every handled input")
    func logsEveryInput() {
        var input = FakeControllerInput()
        let sink = RecordingKeyboardSink()
        let collector = LineCollector()
        let bridge = ControllerBridge(
            profile: Self.wisprTestProfile,
            keyboard: SyntheticKeyboard(sink: sink, accessibility: .fixed(.granted)),
            log: { collector.append($0) }
        )

        bridge.handle(.connected(input.controller))
        bridge.handle(input.press(.micButton))
        bridge.handle(input.release(.micButton))
        bridge.shutdown()

        let lines = collector.lines
        #expect(lines.contains("connected Fake DualSense (fake-1)"))
        #expect(lines.contains("micButton pressed: beginHold(control+option+space) -> emitted"))
        #expect(lines.contains("micButton released: endHold(control+option+space) -> emitted"))
        #expect(lines.contains("shutdown"))
        #expect(!lines.contains(where: { $0.contains("/Users/") }))
    }

    @Test("diagnostics summarize profile, controllers, held keys, and permission")
    func diagnosticsSnapshot() {
        var input = FakeControllerInput()
        let (bridge, _) = makeBridge()

        bridge.handle(.connected(input.controller))
        bridge.handle(input.press(.micButton))

        let diagnostics = bridge.diagnostics
        #expect(diagnostics.profileName == "starter-terminal")
        #expect(diagnostics.connectedControllers == [input.controller])
        #expect(diagnostics.heldKeys == ["control", "option", "space"])
        #expect(diagnostics.accessibility.isUsable)
        #expect(diagnostics.bindingSummary.contains("cross -> tap return"))
        #expect(diagnostics.text.contains("Profile: starter-terminal"))
        #expect(diagnostics.text.contains("Held keys: control, option, space"))
        #expect(diagnostics.text.contains("Controllers: Fake DualSense (fake-1)"))
    }

    @Test("diagnostics never claim a run loop is active")
    func diagnosticsDoNotClaimToBeRunning() {
        let (bridge, _) = makeBridge()

        // An idle bridge built only to report state must not print a line that
        // reads as though input is being handled.
        #expect(!bridge.diagnostics.text.contains("Running"))
        #expect(bridge.diagnostics.text.contains("Controllers: none connected"))
    }

    @Test("swapping profiles mid-session releases the previous hold")
    func swappingProfilesReleasesHolds() throws {
        var input = FakeControllerInput()
        let (bridge, sink) = makeBridge()
        let custom = ControllerProfile(
            name: "custom",
            bindings: [.r1: .hold(try KeyStroke(parsing: "cmd+shift+d"))]
        )

        bridge.handle(input.press(.micButton))
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
