import Testing

@testable import DualSenseBridgeCore

@Suite("held controller buttons repeat editing keys like a keyboard")
struct KeyRepeatBridgeTests {
    @Test("Square deletes immediately, repeats after the delay, and stops on release")
    func squareRepeatsUntilReleased() {
        let controller = ControllerIdentity(id: "fake-1", displayName: "Fake DualSense")
        let sink = RecordingKeyboardSink()
        let bridge = ControllerBridge(
            profile: .starterTerminal,
            keyboard: SyntheticKeyboard(sink: sink, accessibility: .fixed(.granted)),
            keyRepeatSettings: KeyRepeatSettings(initialDelay: 0.4, interval: 0.05)
        )

        bridge.handle(button(.square, .pressed, at: 10, from: controller))
        #expect(sink.emissions == [.down(.delete)])

        bridge.tick(at: 10.399)
        #expect(sink.emissions == [.down(.delete)])

        bridge.tick(at: 10.4)
        bridge.tick(at: 10.45)
        #expect(sink.emissions == [.down(.delete), .repeat(.delete), .repeat(.delete)])

        bridge.handle(button(.square, .released, at: 10.46, from: controller))
        bridge.tick(at: 11)
        #expect(
            sink.emissions
                == [.down(.delete), .repeat(.delete), .repeat(.delete), .up(.delete)]
        )
        #expect(bridge.heldKeys.isEmpty)
    }

    @Test("R3 keeps Ctrl-S down for the physical click instead of emitting a zero-duration tap")
    func r3UsesPhysicalButtonDwell() {
        let controller = ControllerIdentity(id: "fake-1", displayName: "Fake DualSense")
        let sink = RecordingKeyboardSink()
        let bridge = ControllerBridge(
            profile: .starterTerminal,
            keyboard: SyntheticKeyboard(sink: sink, accessibility: .fixed(.granted))
        )

        bridge.handle(button(.r3, .pressed, at: 20, from: controller))
        #expect(sink.emissions == [.down(.control), .down(.s)])
        #expect(bridge.heldKeys == [.control, .s])

        bridge.handle(button(.r3, .released, at: 20.1, from: controller))
        #expect(
            sink.emissions
                == [.down(.control), .down(.s), .up(.s), .up(.control)]
        )
        #expect(bridge.heldKeys.isEmpty)
    }

    @Test("disconnect releases a repeating Backspace and cancels future repeats")
    func disconnectStopsSquareRepeat() {
        let controller = ControllerIdentity(id: "fake-1", displayName: "Fake DualSense")
        let sink = RecordingKeyboardSink()
        let bridge = ControllerBridge(
            profile: .starterTerminal,
            keyboard: SyntheticKeyboard(sink: sink, accessibility: .fixed(.granted)),
            keyRepeatSettings: KeyRepeatSettings(initialDelay: 0.4, interval: 0.05)
        )

        bridge.handle(button(.square, .pressed, at: 30, from: controller))
        bridge.handle(.disconnected(controller))
        bridge.tick(at: 31)

        #expect(sink.emissions == [.down(.delete), .up(.delete)])
        #expect(bridge.heldKeys.isEmpty)
    }

    private func button(
        _ control: ControllerControl,
        _ phase: ControllerEventPhase,
        at timestamp: Double,
        from controller: ControllerIdentity
    ) -> ControllerInput {
        .button(
            ControllerEvent(
                controller: controller,
                control: control,
                phase: phase,
                timestamp: timestamp,
                source: .fake
            )
        )
    }
}
