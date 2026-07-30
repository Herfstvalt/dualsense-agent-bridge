import Foundation
import Testing

@testable import DualSenseBridgeCore

/// A recording sink whose button transitions can be made to fail selectively.
///
/// `FailingPointerSink` fails everything, which cannot express the case that
/// matters most here: a button that went down successfully and then could not be
/// lifted.
final class ScriptedPointerSink: PointerSink {
    struct Failure: Error {}

    var failsPress = false
    var failsRelease = false
    private(set) var emissions: [PointerEmission] = []
    private var leftButtonIsDown = false
    private var rightButtonIsDown = false

    func moveCursor(dx: Int, dy: Int) throws {
        if leftButtonIsDown {
            emissions.append(.leftDrag(dx: dx, dy: dy))
        } else if rightButtonIsDown {
            emissions.append(.drag(dx: dx, dy: dy))
        } else {
            emissions.append(.move(dx: dx, dy: dy))
        }
    }

    func scroll(dx: Int, dy: Int) throws {
        emissions.append(.scroll(dx: dx, dy: dy))
    }

    func pressLeftButton() throws {
        if failsPress { throw Failure() }
        leftButtonIsDown = true
        emissions.append(.leftButtonDown)
    }

    func releaseLeftButton() throws {
        leftButtonIsDown = false
        if failsRelease { throw Failure() }
        emissions.append(.leftButtonUp)
    }

    func pressRightButton() throws {
        // Only a posted down may promote later motion to a drag, exactly as in
        // `CoreGraphicsPointerSink`.
        if failsPress { throw Failure() }
        rightButtonIsDown = true
        emissions.append(.rightButtonDown)
    }

    func releaseRightButton() throws {
        // Cleared before the failure, again mirroring the real sink: a release
        // that could not be posted must still stop drag promotion.
        rightButtonIsDown = false
        if failsRelease { throw Failure() }
        emissions.append(.rightButtonUp)
    }

    var transcript: [String] { emissions.map(\.description) }
}

@Suite("the pointer boundary never latches the right mouse button")
struct PointerButtonTests {
    @Test("a press is refused without Accessibility permission and holds nothing")
    func pressRefusedWithoutPermission() {
        let sink = RecordingPointerSink()
        let pointer = SyntheticPointer(sink: sink, accessibility: .fixed(.denied))

        #expect(pointer.perform(.pressRightButton).isRefusal)
        #expect(pointer.isRightButtonDown == false)
        #expect(sink.emissions.isEmpty)
    }

    @Test("a failed press leaves nothing held, so the next press still works")
    func failedPressLeavesNothingHeld() {
        let sink = ScriptedPointerSink()
        let pointer = SyntheticPointer(sink: sink, accessibility: .fixed(.granted))
        sink.failsPress = true

        #expect(pointer.perform(.pressRightButton) == .failed(reason: SyntheticPointer.sinkFailureReason))
        // The whole point: believing a failed button is down would make the next
        // press a no-op, so R2 would be dead until the process restarted.
        #expect(pointer.isRightButtonDown == false)

        sink.failsPress = false
        #expect(pointer.perform(.pressRightButton) == .emitted)
        #expect(sink.transcript == ["right button down"])
    }

    @Test("motion after a failed press is an ordinary move, not a phantom drag")
    func failedPressDoesNotDrag() {
        let sink = ScriptedPointerSink()
        let pointer = SyntheticPointer(sink: sink, accessibility: .fixed(.granted))
        sink.failsPress = true

        _ = pointer.perform(.pressRightButton)
        pointer.perform(.moveCursor(dx: 3, dy: 0))

        #expect(sink.transcript == ["move dx=+3 dy=+0"])
    }

    @Test("a failed release still clears the hold rather than latching it")
    func failedReleaseClearsTheHold() {
        let sink = ScriptedPointerSink()
        let pointer = SyntheticPointer(sink: sink, accessibility: .fixed(.granted))

        #expect(pointer.perform(.pressRightButton) == .emitted)
        sink.failsRelease = true
        #expect(pointer.perform(.releaseRightButton) == .failed(reason: SyntheticPointer.sinkFailureReason))
        // Nothing here can fix the physical button, but continuing to emit drag
        // events on every stick push would make it considerably worse.
        #expect(pointer.isRightButtonDown == false)

        pointer.perform(.moveCursor(dx: 2, dy: 0))
        #expect(sink.transcript == ["right button down", "move dx=+2 dy=+0"])
    }

    @Test("a release is never refused, so a revoked permission cannot latch the button")
    func releaseIsNeverRefused() {
        let accessibility = MutableAccessibility(.granted)
        let sink = RecordingPointerSink()
        let pointer = SyntheticPointer(sink: sink, accessibility: accessibility.capability)

        #expect(pointer.perform(.pressRightButton) == .emitted)
        accessibility.revoke()

        #expect(pointer.perform(.releaseRightButton) == .emitted)
        #expect(pointer.isRightButtonDown == false)
        #expect(sink.transcript == ["right button down", "right button up"])
    }

    @Test("a cleanup sweep releases a held button even after permission is revoked")
    func cleanupSweepBypassesPermission() {
        let accessibility = MutableAccessibility(.granted)
        let sink = RecordingPointerSink()
        let pointer = SyntheticPointer(sink: sink, accessibility: accessibility.capability)

        pointer.perform(.pressRightButton)
        accessibility.revoke()
        pointer.releaseAllPointerButtons()

        #expect(pointer.isRightButtonDown == false)
        #expect(sink.transcript == ["right button down", "right button up"])
    }

    @Test("a sweep with nothing held emits nothing at all")
    func sweepWithNothingHeld() {
        let sink = RecordingPointerSink()
        let pointer = SyntheticPointer(sink: sink, accessibility: .fixed(.granted))

        #expect(pointer.perform(.releaseAllPointerButtons) == .noOutput)
        pointer.releaseAllPointerButtons()

        #expect(sink.emissions.isEmpty)
    }

    @Test("a cleanup sweep releases both mouse buttons in a stable order")
    func cleanupSweepReleasesBothButtons() {
        let sink = RecordingPointerSink()
        let pointer = SyntheticPointer(sink: sink, accessibility: .fixed(.granted))

        pointer.perform(.pressLeftButton)
        pointer.perform(.pressRightButton)
        #expect(pointer.perform(.releaseAllPointerButtons) == .emitted)

        #expect(
            sink.transcript == [
                "left button down",
                "right button down",
                "left button up",
                "right button up",
            ]
        )
        #expect(!pointer.isLeftButtonDown)
        #expect(!pointer.isRightButtonDown)
    }

    @Test("a duplicate press emits no second button-down")
    func duplicatePressEmitsOnce() {
        let sink = RecordingPointerSink()
        let pointer = SyntheticPointer(sink: sink, accessibility: .fixed(.granted))

        #expect(pointer.perform(.pressRightButton) == .emitted)
        #expect(pointer.perform(.pressRightButton) == .noOutput)
        #expect(pointer.perform(.releaseRightButton) == .emitted)
        #expect(pointer.perform(.releaseRightButton) == .noOutput)

        #expect(sink.transcript == ["right button down", "right button up"])
    }

    @Test("resetting the motion remainder does not release a held button")
    func resetDoesNotReleaseTheButton() {
        let sink = RecordingPointerSink()
        let pointer = SyntheticPointer(sink: sink, accessibility: .fixed(.granted))

        pointer.perform(.pressRightButton)
        // Every stick return-to-centre calls this; a drag must survive a pause.
        pointer.reset()

        #expect(pointer.isRightButtonDown)
        #expect(sink.transcript == ["right button down"])
    }

    @Test("pointer-button outcomes describe themselves for diagnostics")
    func outcomeDescriptions() {
        #expect(PointerButtonOutcome.emitted.description == "emitted")
        #expect(PointerButtonOutcome.noOutput.description == "no output")
        #expect(PointerButtonOutcome.refused(reason: "no permission").description == "refused: no permission")
        #expect(PointerButtonOutcome.failed(reason: "rejected").description == "failed: rejected")
        #expect(PointerButtonOutcome.refused(reason: "x").isRefusal)
        #expect(PointerButtonOutcome.failed(reason: "x").isRefusal == false)
    }

    @Test("pointer-button actions describe themselves for diagnostics")
    func actionDescriptions() {
        #expect(PointerButtonAction.pressLeftButton.description == "pressLeftButton")
        #expect(PointerButtonAction.releaseLeftButton.description == "releaseLeftButton")
        #expect(PointerButtonAction.pressRightButton.description == "pressRightButton")
        #expect(PointerButtonAction.releaseRightButton.description == "releaseRightButton")
        #expect(PointerButtonAction.releaseAllPointerButtons.description == "releaseAllPointerButtons")
    }
}
