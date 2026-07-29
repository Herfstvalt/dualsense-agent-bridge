import Foundation
import Testing

@testable import DualSenseBridgeCore

/// A pointer sink that fails on demand, so the failure path can be exercised
/// without a window server.
final class FailingPointerSink: PointerSink {
    struct Failure: Error {}

    private(set) var attempts = 0

    func moveCursor(dx: Int, dy: Int) throws {
        attempts += 1
        throw Failure()
    }

    func scroll(dx: Int, dy: Int) throws {
        attempts += 1
        throw Failure()
    }
}

@Suite("the synthetic pointer quantizes motion and honors the permission boundary")
struct SyntheticPointerTests {
    private func makePointer(
        status: AccessibilityStatus = .granted
    ) -> (SyntheticPointer, RecordingPointerSink) {
        let sink = RecordingPointerSink()
        return (SyntheticPointer(sink: sink, accessibility: .fixed(status)), sink)
    }

    @Test("sub-pixel motion accumulates until it is worth a whole pixel")
    func subPixelMotionAccumulates() {
        let (pointer, sink) = makePointer()

        // Four tenths of a pixel per tick: nothing for two ticks, then a pixel.
        #expect(pointer.perform(.moveCursor(dx: 0.4, dy: 0)) == .accumulated)
        #expect(pointer.perform(.moveCursor(dx: 0.4, dy: 0)) == .accumulated)
        #expect(pointer.perform(.moveCursor(dx: 0.4, dy: 0)) == .emitted(dx: 1, dy: 0))

        #expect(sink.emissions == [.move(dx: 1, dy: 0)])
    }

    @Test("accumulated remainders are not lost, so slow motion still travels")
    func slowMotionStillTravels() {
        let (pointer, sink) = makePointer()

        // A quarter pixel per tick, exactly representable, so the expected total
        // is arithmetic rather than a tolerance on accumulated drift.
        for _ in 0..<40 {
            pointer.perform(.moveCursor(dx: 0.25, dy: -0.25))
        }

        let moved = sink.emissions.reduce(into: (x: 0, y: 0)) { total, emission in
            if case .move(let dx, let dy) = emission {
                total.x += dx
                total.y += dy
            }
        }
        #expect(moved.x == 10)
        #expect(moved.y == -10)
    }

    @Test("motion is truncated towards zero so the cursor never overshoots")
    func motionTruncatesTowardsZero() {
        let (pointer, sink) = makePointer()

        #expect(pointer.perform(.moveCursor(dx: 1.9, dy: -1.9)) == .emitted(dx: 1, dy: -1))
        #expect(sink.emissions == [.move(dx: 1, dy: -1)])
    }

    @Test("scroll and pointer remainders are tracked separately")
    func scrollAndPointerAreIndependent() {
        let (pointer, sink) = makePointer()

        pointer.perform(.moveCursor(dx: 0.6, dy: 0))
        pointer.perform(.scroll(dx: 0, dy: 0.6))
        pointer.perform(.moveCursor(dx: 0.6, dy: 0))

        #expect(sink.emissions == [.move(dx: 1, dy: 0)])

        pointer.perform(.scroll(dx: 0, dy: 0.6))
        #expect(sink.emissions == [.move(dx: 1, dy: 0), .scroll(dx: 0, dy: 1)])
    }

    @Test("a batch of outputs reports one outcome each")
    func batchReportsEveryOutcome() {
        let (pointer, _) = makePointer()

        let outcomes = pointer.performAll([
            .moveCursor(dx: 2, dy: 0),
            .scroll(dx: 0, dy: 0.1),
        ])

        #expect(outcomes == [.emitted(dx: 2, dy: 0), .accumulated])
    }

    @Test("resetting drops the sub-pixel remainder so a new push starts clean")
    func resetDropsRemainder() {
        let (pointer, sink) = makePointer()

        pointer.perform(.moveCursor(dx: 0.9, dy: 0.9))
        pointer.reset()
        pointer.perform(.moveCursor(dx: 0.9, dy: 0.9))

        #expect(sink.emissions.isEmpty)
    }

    @Test("pointer output is refused without Accessibility permission")
    func refusedWithoutPermission() {
        let (pointer, sink) = makePointer(status: .denied)

        let outcome = pointer.perform(.moveCursor(dx: 10, dy: 10))

        #expect(outcome.isRefusal)
        #expect(sink.emissions.isEmpty)
    }

    @Test("a refusal does not bank motion that would jump once permission arrives")
    func refusalDoesNotBankMotion() {
        let accessibility = MutableAccessibility(.denied)
        let sink = RecordingPointerSink()
        let pointer = SyntheticPointer(sink: sink, accessibility: accessibility.capability)

        for _ in 0..<50 {
            pointer.perform(.moveCursor(dx: 20, dy: 20))
        }
        accessibility.grant()
        pointer.perform(.moveCursor(dx: 0.5, dy: 0.5))

        #expect(sink.emissions.isEmpty)
    }

    @Test("a sink failure is reported and does not latch the remainder")
    func sinkFailureIsReported() {
        let sink = FailingPointerSink()
        let pointer = SyntheticPointer(sink: sink, accessibility: .fixed(.granted))

        let outcome = pointer.perform(.moveCursor(dx: 3, dy: 0))

        #expect(outcome == .failed(reason: SyntheticPointer.sinkFailureReason))
        #expect(sink.attempts == 1)
    }

    @Test("an absurd delta is bounded instead of trapping on conversion")
    func absurdDeltasAreBounded() {
        let (pointer, sink) = makePointer()

        // Regression: converting a delta this large to Int used to trap, on the
        // one code path that must never crash while a stick is held.
        let outcome = pointer.perform(.moveCursor(dx: 1e300, dy: -1e300))

        #expect(
            outcome
                == .emitted(
                    dx: Int(SyntheticPointer.maximumUnitsPerOutput),
                    dy: -Int(SyntheticPointer.maximumUnitsPerOutput)
                )
        )
        #expect(sink.emissions.count == 1)
    }

    @Test("a non-finite delta moves nothing at all")
    func nonFiniteDeltasAreIgnored() {
        let (pointer, sink) = makePointer()

        #expect(pointer.perform(.moveCursor(dx: .nan, dy: .infinity)) == .accumulated)
        #expect(pointer.perform(.scroll(dx: -.infinity, dy: .nan)) == .accumulated)
        #expect(sink.emissions.isEmpty)
    }

    @Test("a non-finite delta cannot poison the carried-over remainder")
    func nonFiniteDeltasLeaveTheRemainderUsable() {
        let (pointer, sink) = makePointer()

        pointer.perform(.moveCursor(dx: .nan, dy: .nan))
        pointer.perform(.moveCursor(dx: 0.6, dy: 0))
        pointer.perform(.moveCursor(dx: 0.6, dy: 0))

        #expect(sink.emissions == [.move(dx: 1, dy: 0)])
    }

    @Test("outcomes describe themselves for diagnostics")
    func outcomeDescriptions() {
        #expect(NavigationOutcome.emitted(dx: 3, dy: -2).description == "emitted dx=3 dy=-2")
        #expect(NavigationOutcome.accumulated.description == "below one pixel")
        #expect(NavigationOutcome.refused(reason: "no permission").description == "refused: no permission")
        #expect(NavigationOutcome.failed(reason: "boom").description == "failed: boom")
        #expect(!NavigationOutcome.accumulated.isRefusal)
    }

    @Test("the pointer reports the same permission state as the keyboard")
    func permissionReport() {
        let (pointer, _) = makePointer(status: .denied)

        #expect(!pointer.accessibilityReport.isUsable)
        #expect(pointer.accessibilityReport.remediationSteps.count == 4)
    }
}

@Suite("dry-run motion logging is bounded rather than one line per tick")
struct LoggingPointerSinkTests {
    /// A clock the test advances by hand, so throttling is deterministic.
    private final class TestClock {
        var now: Double = 100
    }

    @Test("many tiny motions collapse into one throttled summary line")
    func motionIsSummarized() throws {
        let clock = TestClock()
        let lines = LineCollector()
        let sink = LoggingPointerSink(
            interval: 0.5,
            now: { clock.now },
            log: { lines.append($0) }
        )

        for sample in 0..<60 {
            // An exact clock, so the throttle boundary is not decided by
            // accumulated floating-point drift.
            clock.now = 100 + Double(sample) * 0.01
            try sink.moveCursor(dx: 2, dy: -1)
        }

        // 60 events across 0.6 seconds must not produce 60 lines.
        #expect(lines.lines.count == 1)
        let line = try #require(lines.lines.first)
        #expect(line.contains("mouse"))
        #expect(line.contains("dx=+100"))
        #expect(line.contains("dy=-50"))
        #expect(line.contains("50 samples"))
    }

    @Test("nothing is logged before the throttle window closes")
    func quietInsideTheWindow() throws {
        let clock = TestClock()
        let lines = LineCollector()
        let sink = LoggingPointerSink(interval: 0.5, now: { clock.now }, log: { lines.append($0) })

        try sink.moveCursor(dx: 5, dy: 5)
        clock.now += 0.1
        try sink.moveCursor(dx: 5, dy: 5)

        #expect(lines.lines.isEmpty)
    }

    @Test("a flush reports the tail of a gesture so a short flick is still visible")
    func flushReportsTheTail() throws {
        let clock = TestClock()
        let lines = LineCollector()
        let sink = LoggingPointerSink(interval: 0.5, now: { clock.now }, log: { lines.append($0) })

        try sink.moveCursor(dx: 7, dy: 0)
        try sink.scroll(dx: 0, dy: -3)
        sink.flush()

        #expect(lines.lines.count == 2)
        #expect(lines.lines.contains { $0.contains("mouse") && $0.contains("dx=+7") })
        #expect(lines.lines.contains { $0.contains("scroll") && $0.contains("dy=-3") })
    }

    @Test("flushing twice does not repeat a summary")
    func flushIsIdempotent() throws {
        let clock = TestClock()
        let lines = LineCollector()
        let sink = LoggingPointerSink(interval: 0.5, now: { clock.now }, log: { lines.append($0) })

        try sink.moveCursor(dx: 1, dy: 1)
        sink.flush()
        sink.flush()

        #expect(lines.lines.count == 1)
    }

    @Test("mouse and scroll are summarized separately")
    func kindsAreSummarizedSeparately() {
        let clock = TestClock()
        let lines = LineCollector()
        let sink = LoggingPointerSink(interval: 0.5, now: { clock.now }, log: { lines.append($0) })

        for sample in 0..<10 {
            clock.now = 100 + Double(sample) * 0.1
            try? sink.moveCursor(dx: 1, dy: 0)
            try? sink.scroll(dx: 0, dy: 1)
        }

        #expect(lines.lines.count == 2)
        #expect(lines.lines.filter { $0.contains("mouse") }.count == 1)
        #expect(lines.lines.filter { $0.contains("scroll") }.count == 1)
    }

    @Test("a logging sink only ever produces text, which is what makes dry-run safe")
    func loggingSinkOnlyProducesText() throws {
        let lines = LineCollector()
        let sink = LoggingPointerSink(interval: 0.5, now: { 0 }, log: { lines.append($0) })

        try sink.moveCursor(dx: 3, dy: 4)
        sink.flush()

        #expect(lines.lines == ["mouse dx=+3 dy=+4 over 0.00s (1 sample)"])
    }

    @Test("a recording sink keeps a readable transcript for tests")
    func recordingTranscript() throws {
        let sink = RecordingPointerSink()

        try sink.moveCursor(dx: 2, dy: -3)
        try sink.scroll(dx: -1, dy: 4)

        #expect(sink.transcript == ["move dx=+2 dy=-3", "scroll dx=-1 dy=+4"])
        sink.reset()
        #expect(sink.emissions.isEmpty)
    }
}
