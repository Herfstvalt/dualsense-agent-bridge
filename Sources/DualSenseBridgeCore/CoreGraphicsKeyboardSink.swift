#if os(macOS)
import CoreGraphics

/// Emits synthetic key events through CoreGraphics.
///
/// Modifier keys are posted as `flagsChanged` events and the accumulated flag
/// mask is applied to every event, which is what terminal apps and Wispr Flow
/// need in order to see a real chord rather than a bare key. Because this class
/// touches the window server it cannot be covered by automated tests; the
/// manual smoke checklist in `docs/smoke/s1-controller-wispr.md` covers it.
public final class CoreGraphicsKeyboardSink: KeyboardSink {
    public enum Failure: Error, CustomStringConvertible {
        case eventCreationFailed(KeyCode)

        public var description: String {
            switch self {
            case .eventCreationFailed(let key):
                """
                macOS refused to create a synthetic event for "\(key.canonicalName)". \
                This usually means Accessibility permission was revoked while running.
                """
            }
        }
    }

    private let source: CGEventSource?
    private let tapLocation: CGEventTapLocation
    private var heldModifiers: KeyModifiers = []

    public init(tapLocation: CGEventTapLocation = .cghidEventTap) {
        self.source = CGEventSource(stateID: .hidSystemState)
        self.tapLocation = tapLocation
    }

    public func keyDown(_ key: KeyCode) throws {
        try post(key, isDown: true, isRepeat: false)
    }

    public func keyRepeat(_ key: KeyCode) throws {
        try post(key, isDown: true, isRepeat: true)
    }

    public func keyUp(_ key: KeyCode) throws {
        try post(key, isDown: false, isRepeat: false)
    }

    private func post(_ key: KeyCode, isDown: Bool, isRepeat: Bool) throws {
        if let modifier = key.modifier, !isRepeat {
            if isDown {
                heldModifiers.insert(modifier)
            } else {
                heldModifiers.remove(modifier)
            }
        }

        guard
            let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: key.virtualKeyCode,
                keyDown: isDown
            )
        else {
            // Keep bookkeeping honest if the event could not be created.
            if let modifier = key.modifier, isDown, !isRepeat {
                heldModifiers.remove(modifier)
            }
            throw Failure.eventCreationFailed(key)
        }

        if key.modifier != nil {
            event.type = .flagsChanged
        }
        if isRepeat {
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        }
        event.flags = currentFlags
        event.post(tap: tapLocation)
    }

    private var currentFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if heldModifiers.contains(.control) { flags.insert(.maskControl) }
        if heldModifiers.contains(.option) { flags.insert(.maskAlternate) }
        if heldModifiers.contains(.shift) { flags.insert(.maskShift) }
        if heldModifiers.contains(.command) { flags.insert(.maskCommand) }
        return flags
    }
}
#endif
