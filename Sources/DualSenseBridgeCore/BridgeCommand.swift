/// Options for the long-running `run` command.
public struct RunOptions: Hashable, Sendable {
    public var profilePath: String?
    /// When true, actions are logged instead of emitted, so the bridge can be
    /// exercised without Accessibility permission or a live terminal.
    public var dryRun: Bool

    public init(profilePath: String? = nil, dryRun: Bool = false) {
        self.profilePath = profilePath
        self.dryRun = dryRun
    }
}

/// Why the command line could not be understood.
public enum CommandLineError: Error, Hashable, Sendable, CustomStringConvertible {
    case unknownCommand(String)
    case unknownOption(command: String, option: String)
    case missingValue(String)
    case conflictingOptions(String, String)

    public var description: String {
        switch self {
        case .unknownCommand(let name):
            #"Unknown command "\#(name)". Run "dualsense-bridge help" for usage."#
        case .unknownOption(let command, let option):
            #"Command "\#(command)" does not accept the option "\#(option)"."#
        case .missingValue(let option):
            #"Option "\#(option)" needs a value, for example --profile ~/.config/dualsense-bridge/profile.json."#
        case .conflictingOptions(let first, let second):
            #"Options "\#(first)" and "\#(second)" cannot be combined."#
        }
    }
}

/// The parsed CLI request.
public enum BridgeCommand: Hashable, Sendable {
    case help
    case version
    case controls
    case doctor(profilePath: String?)
    /// Print a profile. `starterOnly` prints the built-in profile without
    /// reading any file, which is the safe way to seed a new profile.
    case printProfile(profilePath: String?, starterOnly: Bool)
    case run(RunOptions)

    /// Parses arguments with the program name already removed.
    public init(parsing arguments: [String]) throws {
        guard let first = arguments.first else {
            self = .help
            return
        }
        let rest = Array(arguments.dropFirst())

        switch first {
        case "help", "--help", "-h":
            self = .help
        case "version", "--version":
            self = .version
        case "controls":
            self = .controls
        case "doctor":
            let parsed = try Self.parseOptions(rest, command: "doctor")
            self = .doctor(profilePath: parsed.profilePath)
        case "profile":
            let parsed = try Self.parseOptions(rest, command: "profile", allowStarter: true)
            self = .printProfile(profilePath: parsed.profilePath, starterOnly: parsed.starterOnly)
        case "run":
            let parsed = try Self.parseOptions(rest, command: "run", allowDryRun: true)
            self = .run(RunOptions(profilePath: parsed.profilePath, dryRun: parsed.dryRun))
        default:
            throw CommandLineError.unknownCommand(first)
        }
    }

    private struct ParsedOptions {
        var profilePath: String?
        var dryRun = false
        var starterOnly = false
    }

    private static func parseOptions(
        _ arguments: [String],
        command: String,
        allowDryRun: Bool = false,
        allowStarter: Bool = false
    ) throws -> ParsedOptions {
        var options = ParsedOptions()
        var index = arguments.startIndex

        while index < arguments.endIndex {
            let argument = arguments[index]

            if argument == "--profile" {
                index += 1
                guard index < arguments.endIndex, !arguments[index].hasPrefix("--") else {
                    throw CommandLineError.missingValue("--profile")
                }
                options.profilePath = arguments[index]
            } else if argument.hasPrefix("--profile=") {
                let value = String(argument.dropFirst("--profile=".count))
                guard !value.isEmpty else { throw CommandLineError.missingValue("--profile") }
                options.profilePath = value
            } else if argument == "--dry-run", allowDryRun {
                options.dryRun = true
            } else if argument == "--starter", allowStarter {
                options.starterOnly = true
            } else {
                throw CommandLineError.unknownOption(command: command, option: argument)
            }

            index += 1
        }

        if options.starterOnly, options.profilePath != nil {
            throw CommandLineError.conflictingOptions("--starter", "--profile")
        }

        return options
    }
}

extension BridgeCommand {
    public static let usageText = """
        dualsense-bridge \(BridgeVersion.current)

        Usage:
          dualsense-bridge help                 Show this message
          dualsense-bridge version              Print the version
          dualsense-bridge controls             List controller control names
          dualsense-bridge doctor  [options]    Report permission, profile, and attached controllers
          dualsense-bridge profile [options]    Print a profile as JSON
          dualsense-bridge run     [options]    Bridge controller input to keyboard actions

        Options:
          --profile <path>   Load bindings from a profile JSON file
          --starter          Print the built-in profile without reading a file (profile only)
          --dry-run          Log actions instead of emitting synthetic keys (run only)

        Without --profile the built-in starter profile is used.

        Seed a profile without truncating the file being read; shell redirection
        empties the target before this command runs, so write a temporary file
        and rename it into place:

          dualsense-bridge profile --starter > /tmp/dualsense-profile.json
          mkdir -p ~/.config/dualsense-bridge
          mv /tmp/dualsense-profile.json ~/\(ProfileLoader.defaultRelativePath)

        Run the bridge in a separate terminal or in the background. Cross,
        Circle, and R3 go to whatever window has focus, so the target agent
        session or text field must be focused, not the bridge's own terminal.

        The right stick moves the pointer and the left stick scrolls. Deadzone,
        response curve, speed, and axis inversion live in the profile's
        "navigation" section, so tuning them needs no rebuild. Use --dry-run to
        read the resulting motion as periodic summaries while tuning.

        On a DualSense touch surface, every active contact moves the pointer by
        the contacts' average travel; touchpad input never scrolls or swipes.
        R2 holds the left mouse button; L2 holds the right.
        """

    public static var controlsText: String {
        let controls = ControllerControl.allCases.map { control in
            switch control {
            case .r2:
                "  \(control.rawValue) (reserved: holds the left mouse button)"
            case .l2:
                "  \(control.rawValue) (reserved: holds the right mouse button)"
            case .micButton:
                "  \(control.rawValue) (starter profile leaves this unbound for hardware mute)"
            default:
                "  \(control.rawValue)"
            }
        }

        return (["Controller control names accepted in a profile:"]
            + controls
            + [
                "",
                "Binding kinds: hold, repeat, tap, tapSequence",
                "repeat example: delete (press once, then hold to repeat)",
                "tapSequence example: control+b, n",
            ])
            .joined(separator: "\n")
    }
}
