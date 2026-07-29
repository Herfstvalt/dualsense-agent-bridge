import Foundation

/// A single synthetic pointer event, in whole units.
public enum PointerEmission: Hashable, Sendable, CustomStringConvertible {
    case move(dx: Int, dy: Int)
    case scroll(dx: Int, dy: Int)

    public var description: String {
        switch self {
        case .move(let dx, let dy): String(format: "move dx=%+d dy=%+d", dx, dy)
        case .scroll(let dx, let dy): String(format: "scroll dx=%+d dy=%+d", dx, dy)
        }
    }
}

/// The narrow boundary through which all synthetic pointer output flows.
///
/// Deltas are relative and already whole, because that is the only shape both a
/// window-server sink and a log can honor. Turning a stick into deltas happens
/// above this line; turning deltas into an absolute cursor position happens
/// below it.
public protocol PointerSink: AnyObject {
    func moveCursor(dx: Int, dy: Int) throws
    func scroll(dx: Int, dy: Int) throws
}

/// A sink that records instead of emitting, used by fake-axis tests.
public final class RecordingPointerSink: PointerSink {
    public private(set) var emissions: [PointerEmission] = []

    public init() {}

    public func moveCursor(dx: Int, dy: Int) throws {
        emissions.append(.move(dx: dx, dy: dy))
    }

    public func scroll(dx: Int, dy: Int) throws {
        emissions.append(.scroll(dx: dx, dy: dy))
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
    private var wheel = Window(label: "scroll")

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
        record(dx: dx, dy: dy, in: &mouse)
    }

    public func scroll(dx: Int, dy: Int) throws {
        record(dx: dx, dy: dy, in: &wheel)
    }

    /// Reports whatever has not been summarized yet.
    ///
    /// Without this a short flick would leave no trace at all, which is the one
    /// thing a tuning log must not do. Calling it twice reports nothing the
    /// second time.
    public func flush() {
        let instant = now()
        drain(&mouse, at: instant)
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
