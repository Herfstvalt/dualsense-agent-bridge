import Testing

@testable import DualSenseBridgeCore

/// A sink that fails on a chosen key so partial-chord recovery can be observed.
final class FlakyKeyboardSink: KeyboardSink {
    struct Failure: Error {}

    private(set) var emissions: [KeyEmission] = []
    var failingDownKey: KeyCode?
    var failAllUps = false

    func keyDown(_ key: KeyCode) throws {
        if key == failingDownKey { throw Failure() }
        emissions.append(.down(key))
    }

    func keyUp(_ key: KeyCode) throws {
        if failAllUps { throw Failure() }
        emissions.append(.up(key))
    }
}

@Suite("the synthetic keyboard never leaves a key latched")
struct SyntheticKeyboardTests {
    private let wispr = KeyStroke(key: .space, modifiers: [.control, .option])

    private func makeKeyboard(
        status: AccessibilityStatus = .granted
    ) -> (SyntheticKeyboard, RecordingKeyboardSink) {
        let sink = RecordingKeyboardSink()
        let keyboard = SyntheticKeyboard(sink: sink, accessibility: .fixed(status))
        return (keyboard, sink)
    }

    @Test("a tap presses the chord and releases it in reverse order")
    func tapEmitsCompletePair() {
        let (keyboard, sink) = makeKeyboard()

        #expect(keyboard.perform(.tap(KeyStroke(key: .c, modifiers: .control))) == .emitted)
        #expect(sink.emissions == [.down(.control), .down(.c), .up(.c), .up(.control)])
        #expect(keyboard.heldKeys.isEmpty)
    }

    @Test("a hold keeps the chord down until it ends")
    func holdKeepsKeysDown() {
        let (keyboard, sink) = makeKeyboard()

        #expect(keyboard.perform(.beginHold(wispr)) == .emitted)
        #expect(sink.emissions == [.down(.control), .down(.option), .down(.space)])
        #expect(keyboard.heldKeys == [.control, .option, .space])

        #expect(keyboard.perform(.endHold(wispr)) == .emitted)
        #expect(sink.emissions.suffix(3) == [.up(.space), .up(.option), .up(.control)])
        #expect(keyboard.heldKeys.isEmpty)
    }

    @Test("ending a hold that never began emits nothing")
    func endingUnknownHoldIsHarmless() {
        let (keyboard, sink) = makeKeyboard()

        #expect(keyboard.perform(.endHold(wispr)) == .noOutput)
        #expect(sink.emissions.isEmpty)
    }

    @Test("ending the same hold twice only releases once")
    func duplicateEndHoldReleasesOnce() {
        let (keyboard, sink) = makeKeyboard()

        _ = keyboard.perform(.beginHold(wispr))
        _ = keyboard.perform(.endHold(wispr))
        let afterFirstRelease = sink.emissions.count

        #expect(keyboard.perform(.endHold(wispr)) == .noOutput)
        #expect(sink.emissions.count == afterFirstRelease)
        #expect(keyboard.heldKeys.isEmpty)
    }

    @Test("a modifier shared by two holds is only released once both end")
    func sharedModifierIsReferenceCounted() {
        let (keyboard, sink) = makeKeyboard()
        let interruptHold = KeyStroke(key: .c, modifiers: .control)

        _ = keyboard.perform(.beginHold(wispr))
        sink.reset()

        #expect(keyboard.perform(.beginHold(interruptHold)) == .emitted)
        #expect(sink.emissions == [.down(.c)], "control is already down for the first hold")

        sink.reset()
        _ = keyboard.perform(.endHold(interruptHold))
        #expect(sink.emissions == [.up(.c)], "control must stay down for the remaining hold")
        #expect(keyboard.heldKeys == [.control, .option, .space])

        sink.reset()
        _ = keyboard.perform(.endHold(wispr))
        #expect(sink.emissions == [.up(.space), .up(.option), .up(.control)])
        #expect(keyboard.heldKeys.isEmpty)
    }

    @Test("release-all sweeps every held key in reverse press order")
    func releaseAllSweepsHeldKeys() {
        let (keyboard, sink) = makeKeyboard()

        _ = keyboard.perform(.beginHold(wispr))
        _ = keyboard.perform(.beginHold(KeyStroke(key: .d, modifiers: .command)))
        sink.reset()

        #expect(keyboard.perform(.releaseAllHeldKeys) == .emitted)
        #expect(sink.emissions == [.up(.d), .up(.command), .up(.space), .up(.option), .up(.control)])
        #expect(keyboard.heldKeys.isEmpty)
    }

    @Test("release-all with nothing held emits nothing")
    func releaseAllWithNothingHeld() {
        let (keyboard, sink) = makeKeyboard()

        #expect(keyboard.perform(.releaseAllHeldKeys) == .noOutput)
        #expect(sink.emissions.isEmpty)
    }

    @Test("an unmapped control produces no keyboard output")
    func unmappedProducesNoOutput() {
        let (keyboard, sink) = makeKeyboard()

        #expect(keyboard.perform(.unmapped(.micButton)) == .noOutput)
        #expect(sink.emissions.isEmpty)
    }

    @Test("a partially pressed chord is rolled back when the sink fails")
    func partialChordIsRolledBack() {
        let sink = FlakyKeyboardSink()
        sink.failingDownKey = .space
        let keyboard = SyntheticKeyboard(sink: sink, accessibility: .fixed(.granted))

        let outcome = keyboard.perform(.beginHold(wispr))

        #expect(outcome == .failed(reason: "the keyboard sink rejected a synthetic key event"))
        #expect(sink.emissions == [.down(.control), .down(.option), .up(.option), .up(.control)])
        #expect(keyboard.heldKeys.isEmpty, "a failed Wispr chord must not stay half-held")
    }

    @Test("a failing release still clears the held-key bookkeeping")
    func failingReleaseStillClearsState() {
        let sink = FlakyKeyboardSink()
        let keyboard = SyntheticKeyboard(sink: sink, accessibility: .fixed(.granted))

        _ = keyboard.perform(.beginHold(wispr))
        sink.failAllUps = true

        #expect(keyboard.perform(.releaseAllHeldKeys) == .failed(reason: "the keyboard sink rejected a synthetic key event"))
        #expect(keyboard.heldKeys.isEmpty)
    }

    @Test("synthetic output is refused without Accessibility permission")
    func refusesWithoutAccessibility() {
        let (keyboard, sink) = makeKeyboard(status: .denied)

        let outcome = keyboard.perform(.tap(KeyStroke(key: .return)))

        #expect(outcome == .refused(reason: AccessibilityReport(status: .denied).headline))
        #expect(sink.emissions.isEmpty)
        #expect(keyboard.heldKeys.isEmpty)
    }

    @Test("a refused hold is not recorded as held")
    func refusedHoldIsNotTracked() {
        let (keyboard, sink) = makeKeyboard(status: .denied)

        _ = keyboard.perform(.beginHold(wispr))

        #expect(keyboard.heldKeys.isEmpty)
        #expect(keyboard.perform(.endHold(wispr)) == .refused(reason: AccessibilityReport(status: .denied).headline))
        #expect(sink.emissions.isEmpty)
    }

    @Test("permission that arrives later is picked up without restarting")
    func permissionIsCheckedPerAction() {
        let sink = RecordingKeyboardSink()
        nonisolated(unsafe) var status = AccessibilityStatus.denied
        let keyboard = SyntheticKeyboard(sink: sink, accessibility: AccessibilityCapability { status })

        #expect(keyboard.perform(.tap(KeyStroke(key: .return))).isRefusal)
        status = .granted
        #expect(keyboard.perform(.tap(KeyStroke(key: .return))) == .emitted)
        #expect(sink.emissions == [.down(.return), .up(.return)])
    }

    @Test("a batch of actions reports one outcome each")
    func batchReportsEachOutcome() {
        let (keyboard, _) = makeKeyboard()

        let outcomes = keyboard.performAll([
            .beginHold(wispr),
            .unmapped(.micButton),
            .endHold(wispr),
        ])

        #expect(outcomes == [.emitted, .noOutput, .emitted])
    }

    @Test("shutdown release is available without routing an action")
    func directReleaseForShutdown() {
        let (keyboard, sink) = makeKeyboard()

        _ = keyboard.perform(.beginHold(wispr))
        sink.reset()
        keyboard.releaseAllHeldKeys()

        #expect(sink.emissions == [.up(.space), .up(.option), .up(.control)])
        #expect(keyboard.heldKeys.isEmpty)
    }

    @Test("the recording sink transcript reads as key names for diagnostics")
    func recordingSinkTranscript() {
        let (keyboard, sink) = makeKeyboard()

        _ = keyboard.perform(.tap(KeyStroke(key: .c, modifiers: .control)))

        #expect(sink.transcript == ["down control", "down c", "up c", "up control"])
    }

    @Test("the logging sink reports what a dry run would have emitted")
    func loggingSinkDescribesEmissions() {
        nonisolated(unsafe) var lines: [String] = []
        let keyboard = SyntheticKeyboard(
            sink: LoggingKeyboardSink { lines.append($0) },
            accessibility: .fixed(.granted)
        )

        _ = keyboard.perform(.tap(KeyStroke(key: .return)))

        #expect(lines == ["down return", "up return"])
        #expect(keyboard.heldKeys.isEmpty)
    }
}

@Suite("Accessibility diagnostics explain how to grant permission")
struct AccessibilityDiagnosticsTests {
    @Test("a granted report says synthetic input is ready")
    func grantedReport() {
        let report = AccessibilityReport(status: .granted)

        #expect(report.isUsable)
        #expect(report.headline == "Accessibility permission is granted; synthetic keyboard output is enabled.")
        #expect(report.remediationSteps.isEmpty)
    }

    @Test("a denied report names the exact settings pane and the restart requirement")
    func deniedReport() {
        let report = AccessibilityReport(status: .denied)

        #expect(!report.isUsable)
        #expect(report.headline == "Accessibility permission is missing; synthetic keyboard output is disabled.")
        #expect(
            report.remediationSteps == [
                "Open System Settings > Privacy & Security > Accessibility.",
                "Add the terminal or app that runs dualsense-bridge, then enable its switch.",
                "Quit and relaunch dualsense-bridge so macOS re-reads the permission.",
                "Re-run \"dualsense-bridge doctor\" to confirm the change.",
            ]
        )
    }

    @Test("the report renders as plain diagnostic text without machine details")
    func reportText() {
        let text = AccessibilityReport(status: .denied).diagnosticText

        #expect(text.hasPrefix("Accessibility permission is missing"))
        #expect(text.contains("  1. Open System Settings > Privacy & Security > Accessibility."))
        #expect(!text.contains("/Users/"))
    }
}
