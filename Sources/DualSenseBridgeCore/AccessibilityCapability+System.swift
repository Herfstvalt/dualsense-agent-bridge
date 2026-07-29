#if os(macOS)
import ApplicationServices

extension AccessibilityCapability {
    /// The real macOS capability, backed by `AXIsProcessTrusted()`.
    ///
    /// The check is cheap and is re-read per action, so granting permission
    /// while the bridge is running takes effect without a relaunch of the
    /// bridge process itself. Note that macOS caches trust per process, so a
    /// freshly granted permission may still require quitting the host terminal.
    public static let system = AccessibilityCapability {
        AXIsProcessTrusted() ? .granted : .denied
    }
}
#endif
