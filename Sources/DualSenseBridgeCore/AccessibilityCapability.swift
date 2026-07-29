/// Whether this process may post synthetic input events.
public enum AccessibilityStatus: String, Hashable, Sendable {
    case granted
    case denied
}

/// The capability boundary for macOS Accessibility permission.
///
/// Permission is re-read for every action instead of cached, because a user can
/// grant it while the bridge is running.
public struct AccessibilityCapability: Sendable {
    private let read: @Sendable () -> AccessibilityStatus

    public init(_ read: @escaping @Sendable () -> AccessibilityStatus) {
        self.read = read
    }

    public var status: AccessibilityStatus { read() }

    /// A capability with a constant answer, for tests and dry runs.
    public static func fixed(_ status: AccessibilityStatus) -> AccessibilityCapability {
        AccessibilityCapability { status }
    }
}

/// An explanation of the current permission state that a user can act on.
public struct AccessibilityReport: Hashable, Sendable {
    public let status: AccessibilityStatus

    public init(status: AccessibilityStatus) {
        self.status = status
    }

    public var isUsable: Bool { status == .granted }

    public var headline: String {
        switch status {
        case .granted:
            "Accessibility permission is granted; synthetic keyboard output is enabled."
        case .denied:
            "Accessibility permission is missing; synthetic keyboard output is disabled."
        }
    }

    /// Ordered instructions for granting permission. Intentionally free of
    /// machine-specific paths so diagnostics can be pasted into an issue.
    public var remediationSteps: [String] {
        guard status == .denied else { return [] }
        return [
            "Open System Settings > Privacy & Security > Accessibility.",
            "Add the terminal or app that runs dualsense-bridge, then enable its switch.",
            "Quit and relaunch dualsense-bridge so macOS re-reads the permission.",
            "Re-run \"dualsense-bridge doctor\" to confirm the change.",
        ]
    }

    public var diagnosticText: String {
        ([headline] + remediationSteps.enumerated().map { "  \($0.offset + 1). \($0.element)" })
            .joined(separator: "\n")
    }
}
