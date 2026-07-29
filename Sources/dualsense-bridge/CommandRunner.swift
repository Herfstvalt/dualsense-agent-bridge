import Dispatch
import DualSenseBridgeCore
import Foundation

/// Executes a parsed command. Keeping this separate from `main.swift` keeps the
/// entry point to argument handling and exit codes.
@MainActor
struct CommandRunner {
    private let loader = ProfileLoader()

    func run(_ command: BridgeCommand) throws {
        switch command {
        case .help:
            print(BridgeCommand.usageText)
        case .version:
            print(BridgeVersion.current)
        case .controls:
            print(BridgeCommand.controlsText)
        case .doctor(let path):
            try doctor(profilePath: path)
        case .printProfile(let path, let starterOnly):
            try printProfile(profilePath: path, starterOnly: starterOnly)
        case .run(let options):
            try startBridge(options: options)
        }
    }

    // MARK: - Diagnostics

    private func doctor(profilePath: String?) throws {
        let profile = try loader.loadPreferringDefaultLocation(path: profilePath)
        let keyboard = SyntheticKeyboard(sink: LoggingKeyboardSink { _ in }, accessibility: .system)
        // Discarding sinks: doctor reports what is configured, it never emits.
        let pointer = SyntheticPointer(sink: LoggingPointerSink { _ in }, accessibility: .system)
        let bridge = ControllerBridge(profile: profile, keyboard: keyboard, pointer: pointer)

        // Report what GameController actually sees, so the controller line is
        // not a claim about an idle bridge.
        let attached = GameControllerEventSource.connectedControllerSnapshot()
        for controller in attached {
            bridge.handle(.connected(controller))
        }

        print(bridge.diagnostics.text)
        print("")
        if attached.isEmpty {
            print("No controller is reporting to GameController right now.")
            print("Turn the DualSense on (PS button) or connect it by USB, then re-run doctor.")
        }
        print("Wispr Flow: set its shortcut to the same keys as the hold binding above.")
        print("Run the bridge in a separate terminal so Cross, Circle, and R3 reach the")
        print("focused agent session rather than the bridge's own terminal.")
        print("Stick navigation needs the same Accessibility permission as the keyboard.")
    }

    private func printProfile(profilePath: String?, starterOnly: Bool) throws {
        // --starter never reads a file, so redirecting its output cannot be
        // corrupted by the shell truncating the profile first.
        let profile =
            starterOnly
            ? ControllerProfile.starterTerminal
            : try loader.loadPreferringDefaultLocation(path: profilePath)
        let json = try profile.encodedJSON()
        print(String(decoding: json, as: UTF8.self))
    }

    // MARK: - Run loop

    private func startBridge(options: RunOptions) throws {
        let profile = try loader.loadPreferringDefaultLocation(path: options.profilePath)

        let keyboardSink: any KeyboardSink
        let pointerSink: any PointerSink
        let accessibility: AccessibilityCapability
        // Reports the tail of a gesture on shutdown, so a short flick is not lost
        // between throttle windows. A no-op outside dry-run.
        var flushMotionLog: () -> Void = {}

        if options.dryRun {
            keyboardSink = LoggingKeyboardSink { print("  \($0)") }
            let motionLog = LoggingPointerSink { print("  \($0)") }
            pointerSink = motionLog
            flushMotionLog = { motionLog.flush() }
            accessibility = .fixed(.granted)
            print("DRY RUN: actions are printed and no synthetic keys or pointer events are emitted.")
            print("Stick motion is summarized periodically rather than once per tick.")
        } else {
            keyboardSink = CoreGraphicsKeyboardSink()
            pointerSink = CoreGraphicsPointerSink()
            accessibility = .system

            let report = AccessibilityReport(status: accessibility.status)
            print(report.diagnosticText)
            guard report.isUsable else {
                print("")
                print("Refusing to start: synthetic keyboard and pointer output would be dropped.")
                print("Use \"dualsense-bridge run --dry-run\" to verify bindings meanwhile.")
                throw ExitCode.permissionMissing
            }
        }

        let bridge = ControllerBridge(
            profile: profile,
            keyboard: SyntheticKeyboard(sink: keyboardSink, accessibility: accessibility),
            pointer: SyntheticPointer(sink: pointerSink, accessibility: accessibility)
        ) { line in
            print(line)
        }

        print("Profile: \(profile.name)")
        for line in profile.summaryLines {
            print("  \(line)")
        }
        print("Navigation:")
        for line in profile.navigation.summaryLines {
            print("  \(line)")
        }
        print("Keep this terminal in the background: keys go to the focused window,")
        print("so focus the agent session or text field you want to control.")

        let source = GameControllerEventSource()
        source.start { input in
            bridge.handle(input)
        }
        print(
            "Background controller events: "
                + (source.monitorsBackgroundEvents ? "enabled" : "DISABLED - input would be dropped")
        )
        print("Waiting for a controller. Press Control-C to stop and release all keys.")

        startNavigationTicks(bridge: bridge)
        installSignalHandlers(source: source, bridge: bridge, flushMotionLog: flushMotionLog)
        RunLoop.main.run()
    }

    /// Drives navigation from a clock rather than from input callbacks.
    ///
    /// A thumbstick reports only when its value changes, so a stick held at full
    /// deflection stops reporting. Without this timer the cursor would twitch once
    /// per stick movement instead of gliding while the stick is held.
    private func startNavigationTicks(bridge: ControllerBridge) {
        let interval = bridge.tickInterval
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            // Some leeway lets the system coalesce wakeups; an idle tick is a
            // dictionary check, so this stays cheap when nothing is moving.
            leeway: .milliseconds(2)
        )
        timer.setEventHandler {
            MainActor.assumeIsolated {
                _ = bridge.tick(at: ProcessInfo.processInfo.systemUptime)
            }
        }
        timer.resume()
        Self.navigationTimer = timer
    }

    /// Makes Control-C and `kill` release every held key and stop all motion
    /// before exiting, which is the difference between a clean stop and a latched
    /// modifier or a cursor that keeps drifting.
    private func installSignalHandlers(
        source: GameControllerEventSource,
        bridge: ControllerBridge,
        flushMotionLog: @escaping () -> Void
    ) {
        for signalNumber in [SIGINT, SIGTERM] {
            signal(signalNumber, SIG_IGN)
            let dispatchSource = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            dispatchSource.setEventHandler {
                MainActor.assumeIsolated {
                    print("")
                    Self.navigationTimer?.cancel()
                    Self.navigationTimer = nil
                    source.stop()
                    bridge.shutdown()
                    flushMotionLog()
                    print("Stopped; all synthetic keys released and motion stopped.")
                    exit(0)
                }
            }
            dispatchSource.resume()
            Self.signalSources.append(dispatchSource)
        }
    }

    /// Signal sources and the tick timer must outlive the call that created them.
    private static var signalSources: [any DispatchSourceSignal] = []
    private static var navigationTimer: (any DispatchSourceTimer)?
}

enum ExitCode: Error {
    case permissionMissing
    case badUsage
    case badProfile

    var status: Int32 {
        switch self {
        case .badUsage: 64
        case .badProfile: 65
        case .permissionMissing: 77
        }
    }
}
