import Testing

@testable import DualSenseBridgeCore

@Suite("DualSense touch contacts behave like a compact trackpad")
struct TouchpadNavigationTests {
    private let settings = TouchpadNavigationSettings(
        pointerPixelsPerUnit: 100,
        scrollPixelsPerUnit: 40
    )

    @Test("one finger moves the cursor relative to its first contact point")
    func oneFingerMovesTheCursor() {
        var input = FakeControllerInput()
        var engine = TouchpadNavigationEngine(settings: settings)

        #expect(engine.handle(input.touchEvent(.primary, .began, x: -0.5, y: 0.25)).isEmpty)
        #expect(
            engine.handle(input.touchEvent(.primary, .moved, x: -0.25, y: 0.5))
                == [.moveCursor(dx: 25, dy: -25)]
        )
    }

    @Test("two fingers scroll by their average movement instead of moving the cursor")
    func twoFingersScroll() {
        var input = FakeControllerInput()
        var engine = TouchpadNavigationEngine(settings: settings)

        _ = engine.handle(input.touchEvent(.primary, .began, x: -0.5, y: 0))
        _ = engine.handle(input.touchEvent(.secondary, .began, x: 0.5, y: 0))

        #expect(
            engine.handle(input.touchEvent(.primary, .moved, x: -0.25, y: 0.25))
                == [.scroll(dx: 5, dy: -5)]
        )
        #expect(
            engine.handle(input.touchEvent(.secondary, .moved, x: 0.75, y: 0.25))
                == [.scroll(dx: 5, dy: -5)]
        )
    }

    @Test("placing or lifting a finger never jumps the cursor")
    func contactTransitionsDoNotJump() {
        var input = FakeControllerInput()
        var engine = TouchpadNavigationEngine(settings: settings)

        _ = engine.handle(input.touchEvent(.primary, .began, x: -0.75, y: -0.75))
        #expect(engine.handle(input.touchEvent(.secondary, .began, x: 0.75, y: 0.75)).isEmpty)
        #expect(engine.handle(input.touchEvent(.secondary, .ended, x: 0.75, y: 0.75)).isEmpty)
        #expect(
            engine.handle(input.touchEvent(.primary, .moved, x: -0.5, y: -0.5))
                == [.moveCursor(dx: 25, dy: -25)]
        )
    }

    @Test("a move received without a begin becomes a safe baseline")
    func missingBeginDoesNotJump() {
        var input = FakeControllerInput()
        var engine = TouchpadNavigationEngine(settings: settings)

        #expect(engine.handle(input.touchEvent(.primary, .moved, x: 0.75, y: 0.75)).isEmpty)
        #expect(
            engine.handle(input.touchEvent(.primary, .moved, x: 1, y: 1))
                == [.moveCursor(dx: 25, dy: -25)]
        )
    }

    @Test("disconnect clears only that controller's contact history")
    func disconnectClearsContactHistory() {
        var first = FakeControllerInput(id: "first")
        var second = FakeControllerInput(id: "second")
        var engine = TouchpadNavigationEngine(settings: settings)

        _ = engine.handle(first.touchEvent(.primary, .began, x: 0, y: 0))
        _ = engine.handle(second.touchEvent(.primary, .began, x: 0, y: 0))
        engine.clear(controller: first.controller)

        #expect(engine.handle(first.touchEvent(.primary, .moved, x: 0.5, y: 0)).isEmpty)
        #expect(
            engine.handle(second.touchEvent(.primary, .moved, x: 0.5, y: 0))
                == [.moveCursor(dx: 50, dy: 0)]
        )
    }
}

@Suite("touchpad input reaches the pointer boundary end to end")
struct TouchpadBridgeTests {
    private let settings = TouchpadNavigationSettings(
        pointerPixelsPerUnit: 100,
        scrollPixelsPerUnit: 40
    )

    private func makeBridge(
        log: ((String) -> Void)? = nil
    ) -> (ControllerBridge, RecordingPointerSink, RecordingKeyboardSink) {
        let pointer = RecordingPointerSink()
        let keyboard = RecordingKeyboardSink()
        return (
            ControllerBridge(
                profile: .starterTerminal,
                keyboard: SyntheticKeyboard(sink: keyboard, accessibility: .fixed(.granted)),
                pointer: SyntheticPointer(sink: pointer, accessibility: .fixed(.granted)),
                touchpadSettings: settings,
                log: log
            ),
            pointer,
            keyboard
        )
    }

    @Test("one finger moves the real pointer boundary without typing")
    func oneFingerMovesPointerBoundary() {
        var input = FakeControllerInput()
        let (bridge, pointer, keyboard) = makeBridge()

        bridge.handle(input.touch(.primary, .began, x: -0.5, y: 0.25))
        bridge.handle(input.touch(.primary, .moved, x: -0.25, y: 0.5))

        #expect(pointer.emissions == [.move(dx: 25, dy: -25)])
        #expect(keyboard.emissions.isEmpty)
    }

    @Test("two fingers scroll the real pointer boundary")
    func twoFingersScrollPointerBoundary() {
        var input = FakeControllerInput()
        let (bridge, pointer, _) = makeBridge()

        bridge.handle(input.touch(.primary, .began, x: -0.5, y: 0))
        bridge.handle(input.touch(.secondary, .began, x: 0.5, y: 0))
        bridge.handle(input.touch(.primary, .moved, x: -0.25, y: 0.25))

        #expect(pointer.emissions == [.scroll(dx: 5, dy: -5)])
    }

    @Test("dry-run diagnostics show contact down and up without logging every sample")
    func contactLifecycleIsLogged() {
        let lines = LineCollector()
        var input = FakeControllerInput()
        let (bridge, _, _) = makeBridge(log: { lines.append($0) })

        bridge.handle(input.touch(.primary, .began, x: -0.5, y: 0))
        bridge.handle(input.touch(.primary, .moved, x: -0.25, y: 0))
        bridge.handle(input.touch(.primary, .ended, x: -0.25, y: 0))

        #expect(lines.lines.count == 2)
        #expect(lines.lines.first?.contains("touchpad primary began") == true)
        #expect(lines.lines.last?.contains("touchpad primary ended") == true)
    }
}
