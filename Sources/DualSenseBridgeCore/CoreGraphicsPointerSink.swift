#if os(macOS)
import CoreGraphics
import Foundation

/// Emits synthetic pointer events through CoreGraphics.
///
/// CoreGraphics has no relative cursor move, so a delta becomes "read where the
/// cursor is, add, clamp, post an absolute move". Clamping to the union of the
/// attached displays is the safety property that matters: without it a held
/// stick would walk the cursor to a coordinate no display owns, where it can
/// neither be seen nor recovered with the trackpad.
///
/// Because this class touches the window server it cannot be covered by
/// automated tests; the manual checklist in
/// `docs/smoke/s4-stick-navigation.md` covers it.
public final class CoreGraphicsPointerSink: PointerSink {
    public enum Failure: Error, CustomStringConvertible {
        case cursorPositionUnavailable
        case eventCreationFailed

        public var description: String {
            switch self {
            case .cursorPositionUnavailable:
                """
                macOS would not report the current cursor position, so relative \
                stick motion cannot be applied.
                """
            case .eventCreationFailed:
                """
                macOS refused to create a synthetic pointer event. \
                This usually means Accessibility permission was revoked while running.
                """
            }
        }
    }

    private let tapLocation: CGEventTapLocation
    /// Whether *this* sink has successfully posted a left-button-down that has
    /// not yet been released.
    ///
    /// Tracked here, rather than trusted from above, because a dragged event with
    /// no matching mouse-down is malformed. Only a posted down may promote a move
    /// to that button's drag event.
    private var leftButtonIsDown = false
    /// Whether a right-button-down is currently active.
    private var rightButtonIsDown = false

    public init(tapLocation: CGEventTapLocation = .cghidEventTap) {
        self.tapLocation = tapLocation
    }

    public func moveCursor(dx: Int, dy: Int) throws {
        if leftButtonIsDown {
            try move(dx: dx, dy: dy, as: .leftMouseDragged, button: .left)
        } else if rightButtonIsDown {
            try move(dx: dx, dy: dy, as: .rightMouseDragged, button: .right)
        } else {
            try move(dx: dx, dy: dy, as: .mouseMoved, button: .left)
        }
    }

    public func pressLeftButton() throws {
        // Set only after the event is actually posted: a failed down must not
        // leave later movement pretending to drag.
        try postAtCurrentPosition(.leftMouseDown, button: .left)
        leftButtonIsDown = true
    }

    public func releaseLeftButton() throws {
        // Cleared first, and whatever happens next: if posting the up fails there
        // is nothing this sink can do about the physical button, and continuing to
        // emit drag events would make it worse.
        leftButtonIsDown = false
        try postAtCurrentPosition(.leftMouseUp, button: .left)
    }

    public func pressRightButton() throws {
        try postAtCurrentPosition(.rightMouseDown, button: .right)
        rightButtonIsDown = true
    }

    public func releaseRightButton() throws {
        rightButtonIsDown = false
        try postAtCurrentPosition(.rightMouseUp, button: .right)
    }

    /// Applies a relative delta by reading the cursor, clamping, and posting an
    /// absolute event of the given type.
    private func move(dx: Int, dy: Int, as type: CGEventType, button: CGMouseButton) throws {
        guard let current = CGEvent(source: nil)?.location else {
            throw Failure.cursorPositionUnavailable
        }

        let target = clampToDisplays(
            CGPoint(x: current.x + CGFloat(dx), y: current.y + CGFloat(dy))
        )
        try post(type, at: target, button: button)
    }

    /// Posts an event where the cursor already is, for transitions that must not
    /// move it.
    private func postAtCurrentPosition(_ type: CGEventType, button: CGMouseButton) throws {
        guard let current = CGEvent(source: nil)?.location else {
            throw Failure.cursorPositionUnavailable
        }
        try post(type, at: current, button: button)
    }

    private func post(_ type: CGEventType, at position: CGPoint, button: CGMouseButton) throws {
        guard
            let event = CGEvent(
                mouseEventSource: nil,
                mouseType: type,
                mouseCursorPosition: position,
                mouseButton: button
            )
        else {
            throw Failure.eventCreationFailed
        }
        event.post(tap: tapLocation)
    }

    public func scroll(dx: Int, dy: Int) throws {
        // Pixel units keep stick scrolling smooth; line units would move a
        // terminal buffer in visible jumps.
        //
        // The horizontal wheel axis grows to the *left*, so a positive dx (stick
        // pushed right) is negated here. If a display or app disagrees, the
        // `scroll.invertX` setting fixes it without a rebuild.
        guard
            let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: Int32(clamping: dy),
                wheel2: Int32(clamping: -dx),
                wheel3: 0
            )
        else {
            throw Failure.eventCreationFailed
        }
        event.post(tap: tapLocation)
    }

    /// Keeps a target point on a display the user can actually see.
    ///
    /// A point already on a screen is left exactly as asked. Anything else —
    /// past an edge, or in the gap between two differently sized screens — is
    /// pulled into the nearest screen's bounds, which is the property that stops
    /// a held stick from parking the cursor somewhere unrecoverable.
    private func clampToDisplays(_ point: CGPoint) -> CGPoint {
        let screens = displayBounds()
        guard !screens.isEmpty else { return point }
        if screens.contains(where: { $0.contains(point) }) { return point }

        let nearest =
            screens
            .min { squaredDistance(from: point, to: $0) < squaredDistance(from: point, to: $1) }
            ?? screens[0]
        return CGPoint(
            x: min(max(point.x, nearest.minX), nearest.maxX - 1),
            y: min(max(point.y, nearest.minY), nearest.maxY - 1)
        )
    }

    private func displayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }

        return displays.prefix(Int(count)).map { CGDisplayBounds($0) }
    }

    private func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
#endif
