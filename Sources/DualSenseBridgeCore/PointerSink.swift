import Foundation

/// A single synthetic pointer event, in whole units.
public enum PointerEmission: Hashable, Sendable, CustomStringConvertible {
    case move(dx: Int, dy: Int)
    /// A move made while the right button is down. macOS needs a distinct event
    /// type for this or applications do not track the drag at all.
    case drag(dx: Int, dy: Int)
    case scroll(dx: Int, dy: Int)
    case rightButtonDown
    case rightButtonUp

    public var description: String {
        switch self {
        case .move(let dx, let dy): String(format: "move dx=%+d dy=%+d", dx, dy)
        case .drag(let dx, let dy): String(format: "drag dx=%+d dy=%+d", dx, dy)
        case .scroll(let dx, let dy): String(format: "scroll dx=%+d dy=%+d", dx, dy)
        case .rightButtonDown: "right button down"
        case .rightButtonUp: "right button up"
        }
    }
}

/// The narrow boundary through which all synthetic pointer output flows.
///
/// Deltas are relative and already whole, because that is the only shape both a
/// window-server sink and a log can honor. Turning a stick into deltas happens
/// above this line; turning deltas into an absolute cursor position happens
/// below it.
/// Each method is one macOS pointer event, named per transition rather than
/// taking a state flag, so a half-finished gesture can be unwound the same way
/// `KeyboardSink` unwinds a half-pressed chord.
public protocol PointerSink: AnyObject {
    func moveCursor(dx: Int, dy: Int) throws
    func scroll(dx: Int, dy: Int) throws
    func pressRightButton() throws
    func releaseRightButton() throws
}

/// A sink that records instead of emitting, used by fake-axis tests.
public final class RecordingPointerSink: PointerSink {
    public private(set) var emissions: [PointerEmission] = []
    private var rightButtonIsDown = false

    public init() {}

    public func moveCursor(dx: Int, dy: Int) throws {
        emissions.append(rightButtonIsDown ? .drag(dx: dx, dy: dy) : .move(dx: dx, dy: dy))
    }

    public func scroll(dx: Int, dy: Int) throws {
        emissions.append(.scroll(dx: dx, dy: dy))
    }

    public func pressRightButton() throws {
        rightButtonIsDown = true
        emissions.append(.rightButtonDown)
    }

    public func releaseRightButton() throws {
        rightButtonIsDown = false
        emissions.append(.rightButtonUp)
    }

    /// Human-readable emissions for diagnostics.
    public var transcript: [String] {
        emissions.map(\.description)
    }

    public func reset() {
        emissions.removeAll()
    }
}

/// A sink that reports motion as throttled summaries and emits nothing.
///
/// This backs `dualsense-bridge run --dry-run`, where the point is to read the
/// numbers while tuning. A stick held for one second produces well over a
/// hundred deltas, so logging one line per delta would bury the terminal and
/// make the numbers unreadable; instead each kind of motion is summed and
/// reported at most once per `interval`.
public final class LoggingPointerSink: PointerSink {
    /// One throttle window's worth of motion for a single kind of output.
    private struct Window {
        let label: String
        var startedAt: Double?
        var dx = 0
        var dy = 0
        var samples = 0

        var isEmpty: Bool { samples == 0 }

        mutating func add(dx: Int, dy: Int, at now: Double) {
            if startedAt == nil { startedAt = now }
            self.dx += dx
            self.dy += dy
            samples += 1
        }

        /// The summary for this window, and a reset ready for the next one.
        mutating func drain(at now: Double) -> String? {
            guard !isEmpty else { return nil }
            let duration = now - (startedAt ?? now)
            let line = String(
                format: "%@ dx=%+d dy=%+d over %.2fs (%d %@)",
                label,
                dx,
                dy,
                duration,
                samples,
                samples == 1 ? "sample" : "samples"
            )
            self = Window(label: label)
            return line
        }
    }

    private let interval: Double
    private let now: () -> Double
    private let log: (String) -> Void
    private var mouse = Window(label: "mouse")
    private var drag = Window(label: "drag")
    private var wheel = Window(label: "scroll")
    private var rightButtonIsDown = false

    public init(
        interval: Double = 0.5,
        now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
        log: @escaping (String) -> Void
    ) {
        self.interval = interval
        self.now = now
        self.log = log
    }

    public func moveCursor(dx: Int, dy: Int) throws {
        if rightButtonIsDown {
            record(dx: dx, dy: dy, in: &drag)
        } else {
            record(dx: dx, dy: dy, in: &mouse)
        }
    }

    public func scroll(dx: Int, dy: Int) throws {
        record(dx: dx, dy: dy, in: &wheel)
    }

    public func pressRightButton() throws {
        rightButtonIsDown = true
        report(PointerEmission.rightButtonDown.description)
    }

    public func releaseRightButton() throws {
        rightButtonIsDown = false
        report(PointerEmission.rightButtonUp.description)
    }

    /// Logs a discrete event immediately, after flushing any pending motion.
    ///
    /// Button transitions are rare and each one matters during a smoke test, so
    /// they are never throttled. Flushing first keeps the log in true order:
    /// without it a summary covering motion from before the click would print
    /// after it.
    private func report(_ line: String) {
        flush()
        log(line)
    }

    /// Reports whatever has not been summarized yet.
    ///
    /// Without this a short flick would leave no trace at all, which is the one
    /// thing a tuning log must not do. Calling it twice reports nothing the
    /// second time.
    public func flush() {
        let instant = now()
        drain(&mouse, at: instant)
        drain(&drag, at: instant)
        drain(&wheel, at: instant)
    }

    private func record(dx: Int, dy: Int, in window: inout Window) {
        let instant = now()
        // Close the previous window before the new sample joins it, so a summary
        // always describes exactly the interval it claims.
        if let started = window.startedAt, instant - started >= interval {
            drain(&window, at: instant)
        }
        window.add(dx: dx, dy: dy, at: instant)
    }

    private func drain(_ window: inout Window, at instant: Double) {
        if let line = window.drain(at: instant) {
            log(line)
        }
    }
}
