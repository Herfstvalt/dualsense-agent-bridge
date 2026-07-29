import Foundation

/// What happened when a navigation output reached the pointer boundary.
public enum NavigationOutcome: Hashable, Sendable, CustomStringConvertible {
    /// Whole units were sent to the sink.
    case emitted(dx: Int, dy: Int)
    /// The motion was real but smaller than one unit, so it is being carried
    /// forward rather than thrown away.
    case accumulated
    /// Output was withheld because the Accessibility capability is unavailable.
    case refused(reason: String)
    /// The sink rejected the event.
    case failed(reason: String)

    public var isRefusal: Bool {
        if case .refused = self { return true }
        return false
    }

    public var description: String {
        switch self {
        case .emitted(let dx, let dy): "emitted dx=\(dx) dy=\(dy)"
        case .accumulated: "below one pixel"
        case .refused(let reason): "refused: \(reason)"
        case .failed(let reason): "failed: \(reason)"
        }
    }
}

/// Applies navigation output to a pointer sink in whole units.
///
/// Two concerns live here and nowhere else:
///
/// - **Quantization.** A tick at 120 Hz asks for a fraction of a pixel. Rounding
///   each tick independently would either throw slow motion away or overshoot,
///   so the remainder is carried forward and only whole units are emitted.
/// - **Permission.** Synthetic pointer events need the same Accessibility grant
///   as synthetic keys, re-read per output because it can be granted or revoked
///   while the bridge runs. A refusal also drops the remainder, so motion cannot
///   bank up while permission is missing and then jump when it arrives.
public final class SyntheticPointer {
    static let sinkFailureReason = "the pointer sink rejected a synthetic event"

    /// Carried-over fractions for one kind of output.
    private struct Remainder {
        var x = 0.0
        var y = 0.0

        /// Adds a fractional delta and takes out whatever whole units it makes.
        ///
        /// Truncation is towards zero so the cursor never travels further than
        /// asked; the leftover stays behind for the next tick.
        mutating func take(dx: Double, dy: Double) -> (dx: Int, dy: Int) {
            x += dx
            y += dy
            let wholeX = x < 0 ? x.rounded(.up) : x.rounded(.down)
            let wholeY = y < 0 ? y.rounded(.up) : y.rounded(.down)
            x -= wholeX
            y -= wholeY
            return (Int(wholeX), Int(wholeY))
        }

        mutating func reset() {
            self = Remainder()
        }
    }

    private let sink: any PointerSink
    private let accessibility: AccessibilityCapability
    private var pointerRemainder = Remainder()
    private var scrollRemainder = Remainder()

    public init(sink: any PointerSink, accessibility: AccessibilityCapability) {
        self.sink = sink
        self.accessibility = accessibility
    }

    /// The current permission report, for CLI diagnostics.
    public var accessibilityReport: AccessibilityReport {
        AccessibilityReport(status: accessibility.status)
    }

    @discardableResult
    public func performAll(_ outputs: [NavigationOutput]) -> [NavigationOutcome] {
        outputs.map(perform)
    }

    @discardableResult
    public func perform(_ output: NavigationOutput) -> NavigationOutcome {
        let report = accessibilityReport
        guard report.isUsable else {
            reset()
            return .refused(reason: report.headline)
        }

        switch output {
        case .moveCursor(let dx, let dy):
            let whole = pointerRemainder.take(dx: dx, dy: dy)
            return emit(whole) { try sink.moveCursor(dx: $0, dy: $1) }
        case .scroll(let dx, let dy):
            let whole = scrollRemainder.take(dx: dx, dy: dy)
            return emit(whole) { try sink.scroll(dx: $0, dy: $1) }
        }
    }

    /// Drops the carried-over fractions.
    ///
    /// Called whenever motion stops for any reason — release, disconnect,
    /// shutdown, or a settings change — so the next push starts from rest
    /// instead of inheriting a stale fraction of a pixel.
    public func reset() {
        pointerRemainder.reset()
        scrollRemainder.reset()
    }

    private func emit(
        _ whole: (dx: Int, dy: Int),
        _ send: (Int, Int) throws -> Void
    ) -> NavigationOutcome {
        guard whole.dx != 0 || whole.dy != 0 else { return .accumulated }
        do {
            try send(whole.dx, whole.dy)
        } catch {
            return .failed(reason: Self.sinkFailureReason)
        }
        return .emitted(dx: whole.dx, dy: whole.dy)
    }
}
