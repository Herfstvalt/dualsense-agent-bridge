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

    public var description: String {
        switch self {
        case .unknownCommand(let name):
            #"Unknown command "\#(name)". Run "dualsense-bridge help" for usage."#
        case .unknownOption(let command, let option):
            #"Command "\#(command)" does not accept the option "\#(option)"."#
        case .missingValue(let option):
            #"Option "\#(option)" needs a value, for example --profile ~/.config/dualsense-bridge/profile.json."#
        }
    }
}

/// The parsed CLI request.
public enum BridgeCommand: Hashable, Sendable {
    case help
    case version
    case controls
    case doctor(profilePath: String?)
    case printProfile(profilePath: String?)
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
            self = .doctor(profilePath: try Self.parseProfilePath(rest, command: "doctor"))
        case "profile":
            self = .printProfile(profilePath: try Self.parseProfilePath(rest, command: "profile"))
        case "run":
            self = .run(try Self.parseRunOptions(rest))
        default:
            throw CommandLineError.unknownCommand(first)
        }
    }

    private static func parseProfilePath(_ arguments: [String], command: String) throws -> String? {
        try parseOptions(arguments, command: command, allowDryRun: false).profilePath
    }

    private static func parseRunOptions(_ arguments: [String]) throws -> RunOptions {
        try parseOptions(arguments, command: "run", allowDryRun: true)
    }

    private static func parseOptions(
        _ arguments: [String],
        command: String,
        allowDryRun: Bool
    ) throws -> RunOptions {
        var options = RunOptions()
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
            } else {
                throw CommandLineError.unknownOption(command: command, option: argument)
            }

            index += 1
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
          dualsense-bridge doctor  [options]    Report permission, profile, and controller state
          dualsense-bridge profile [options]    Print the active profile as JSON
          dualsense-bridge run     [options]    Bridge controller input to keyboard actions

        Options:
          --profile <path>   Load bindings from a profile JSON file
          --dry-run          Log actions instead of emitting synthetic keys (run only)

        Without --profile the built-in starter profile is used. Copy it with
        "dualsense-bridge profile" and save it to ~/\(ProfileLoader.defaultRelativePath).
        """

    public static var controlsText: String {
        (["Controller control names accepted in a profile:"]
            + ControllerControl.allCases.map { "  \($0.rawValue)" })
            .joined(separator: "\n")
    }
}
