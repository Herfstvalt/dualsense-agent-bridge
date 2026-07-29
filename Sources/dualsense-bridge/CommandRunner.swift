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
        case .printProfile(let path):
            try printProfile(profilePath: path)
        case .run(let options):
            try startBridge(options: options)
        }
    }

    // MARK: - Diagnostics

    private func doctor(profilePath: String?) throws {
        let profile = try loader.loadPreferringDefaultLocation(path: profilePath)
        let keyboard = SyntheticKeyboard(sink: LoggingKeyboardSink { _ in }, accessibility: .system)
        let bridge = ControllerBridge(profile: profile, keyboard: keyboard)

        print(bridge.diagnostics.text)
        print("")
        print("Wispr Flow: set its shortcut to the same keys as the hold binding above.")
        print("Controllers are discovered while \"dualsense-bridge run\" is active.")
    }

    private func printProfile(profilePath: String?) throws {
        let profile = try loader.loadPreferringDefaultLocation(path: profilePath)
        let json = try profile.encodedJSON()
        print(String(decoding: json, as: UTF8.self))
    }

    // MARK: - Run loop

    private func startBridge(options: RunOptions) throws {
        let profile = try loader.loadPreferringDefaultLocation(path: options.profilePath)

        let sink: any KeyboardSink
        let accessibility: AccessibilityCapability
        if options.dryRun {
            sink = LoggingKeyboardSink { print("  \($0)") }
            accessibility = .fixed(.granted)
            print("DRY RUN: actions are printed and no synthetic keys are emitted.")
        } else {
            sink = CoreGraphicsKeyboardSink()
            accessibility = .system

            let report = AccessibilityReport(status: accessibility.status)
            print(report.diagnosticText)
            guard report.isUsable else {
                print("")
                print("Refusing to start: synthetic keyboard output would be dropped.")
                print("Use \"dualsense-bridge run --dry-run\" to verify bindings meanwhile.")
                throw ExitCode.permissionMissing
            }
        }

        let keyboard = SyntheticKeyboard(sink: sink, accessibility: accessibility)
        let bridge = ControllerBridge(profile: profile, keyboard: keyboard) { line in
            print(line)
        }

        print("Profile: \(profile.name)")
        for line in profile.summaryLines {
            print("  \(line)")
        }
        print("Waiting for a controller. Press Control-C to stop and release all keys.")

        let source = GameControllerEventSource()
        source.start { input in
            bridge.handle(input)
        }

        installSignalHandlers(source: source, bridge: bridge)
        RunLoop.main.run()
    }

    /// Makes Control-C and `kill` release every held key before exiting, which
    /// is the difference between a clean stop and a latched modifier.
    private func installSignalHandlers(source: GameControllerEventSource, bridge: ControllerBridge) {
        for signalNumber in [SIGINT, SIGTERM] {
            signal(signalNumber, SIG_IGN)
            let dispatchSource = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            dispatchSource.setEventHandler {
                MainActor.assumeIsolated {
                    print("")
                    source.stop()
                    bridge.shutdown()
                    print("Stopped; all synthetic keys released.")
                    exit(0)
                }
            }
            dispatchSource.resume()
            Self.signalSources.append(dispatchSource)
        }
    }

    /// Signal sources must outlive the call that created them.
    private static var signalSources: [any DispatchSourceSignal] = []
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
