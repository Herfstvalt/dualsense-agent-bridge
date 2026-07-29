import Foundation
import Testing

@testable import DualSenseBridgeCore

@Suite("the CLI surface is parsed before anything touches the system")
struct CommandLineTests {
    @Test("no arguments prints help rather than starting synthetic input")
    func noArgumentsIsHelp() throws {
        #expect(try BridgeCommand(parsing: []) == .help)
    }

    @Test("help and version have conventional spellings")
    func helpAndVersionSpellings() throws {
        for argument in ["help", "--help", "-h"] {
            #expect(try BridgeCommand(parsing: [argument]) == .help)
        }
        for argument in ["version", "--version"] {
            #expect(try BridgeCommand(parsing: [argument]) == .version)
        }
    }

    @Test("doctor and controls take no required arguments")
    func diagnosticCommands() throws {
        #expect(try BridgeCommand(parsing: ["doctor"]) == .doctor(profilePath: nil))
        #expect(try BridgeCommand(parsing: ["controls"]) == .controls)
    }

    @Test("a profile path can be supplied to doctor, profile, and run")
    func profilePathIsAccepted() throws {
        #expect(try BridgeCommand(parsing: ["doctor", "--profile", "p.json"]) == .doctor(profilePath: "p.json"))
        #expect(
            try BridgeCommand(parsing: ["profile", "--profile", "p.json"])
                == .printProfile(profilePath: "p.json", starterOnly: false)
        )
        #expect(
            try BridgeCommand(parsing: ["run", "--profile", "p.json"])
                == .run(RunOptions(profilePath: "p.json", dryRun: false))
        )
        #expect(try BridgeCommand(parsing: ["run", "--profile=p.json"]) == .run(RunOptions(profilePath: "p.json")))
    }

    @Test("profile --starter exports the built-in profile without reading a file")
    func starterOnlyExport() throws {
        #expect(
            try BridgeCommand(parsing: ["profile", "--starter"])
                == .printProfile(profilePath: nil, starterOnly: true)
        )
    }

    @Test("--starter and --profile together are refused instead of silently ranked")
    func starterAndProfileConflict() {
        #expect(throws: CommandLineError.conflictingOptions("--starter", "--profile")) {
            try BridgeCommand(parsing: ["profile", "--starter", "--profile", "p.json"])
        }
        #expect(
            CommandLineError.conflictingOptions("--starter", "--profile").description
                == #"Options "--starter" and "--profile" cannot be combined."#
        )
    }

    @Test("--starter only applies to the profile command")
    func starterIsProfileOnly() {
        #expect(throws: CommandLineError.unknownOption(command: "run", option: "--starter")) {
            try BridgeCommand(parsing: ["run", "--starter"])
        }
        #expect(throws: CommandLineError.unknownOption(command: "doctor", option: "--starter")) {
            try BridgeCommand(parsing: ["doctor", "--starter"])
        }
    }

    @Test("run supports a dry run that emits no synthetic keys")
    func dryRunFlag() throws {
        #expect(try BridgeCommand(parsing: ["run", "--dry-run"]) == .run(RunOptions(dryRun: true)))
        #expect(
            try BridgeCommand(parsing: ["run", "--dry-run", "--profile", "p.json"])
                == .run(RunOptions(profilePath: "p.json", dryRun: true))
        )
    }

    @Test("an unknown command is refused with usage guidance")
    func unknownCommandIsRefused() {
        #expect(throws: CommandLineError.unknownCommand("frobnicate")) {
            try BridgeCommand(parsing: ["frobnicate"])
        }
        #expect(
            CommandLineError.unknownCommand("frobnicate").description
                == #"Unknown command "frobnicate". Run "dualsense-bridge help" for usage."#
        )
    }

    @Test("an unknown option names the command it was given to")
    func unknownOptionIsRefused() {
        #expect(throws: CommandLineError.unknownOption(command: "run", option: "--fast")) {
            try BridgeCommand(parsing: ["run", "--fast"])
        }
    }

    @Test("a missing option value is refused instead of defaulted")
    func missingOptionValueIsRefused() {
        #expect(throws: CommandLineError.missingValue("--profile")) {
            try BridgeCommand(parsing: ["run", "--profile"])
        }
        #expect(
            CommandLineError.missingValue("--profile").description
                == #"Option "--profile" needs a value, for example --profile ~/.config/dualsense-bridge/profile.json."#
        )
    }

    @Test("usage text lists every command and stays machine independent")
    func usageTextListsCommands() {
        let usage = BridgeCommand.usageText

        for command in ["help", "version", "doctor", "controls", "profile", "run"] {
            #expect(usage.contains(command))
        }
        #expect(usage.contains("--dry-run"))
        #expect(usage.contains("--starter"))
        #expect(!usage.contains("/Users/"))
    }

    @Test("usage text tells the user to redirect an export through a temporary file")
    func usageTextDocumentsSafeExport() {
        let usage = BridgeCommand.usageText

        // Redirecting straight onto the default path truncates the file that
        // this command may be about to read.
        #expect(usage.contains("profile --starter > /tmp/dualsense-profile.json"))
        #expect(usage.contains("mv /tmp/dualsense-profile.json"))
    }

    @Test("usage text warns that the bridge needs its own terminal")
    func usageTextDocumentsFocus() {
        #expect(BridgeCommand.usageText.contains("separate terminal"))
    }

    @Test("the controls listing names every supported control")
    func controlsListing() {
        let listing = BridgeCommand.controlsText

        #expect(listing.contains("cross"))
        #expect(listing.contains("r3"))
        #expect(listing.contains("micButton"))
        #expect(listing.split(separator: "\n").count >= ControllerControl.allCases.count)
    }
}

@Suite("profiles load from disk with actionable errors")
struct ProfileLoaderTests {
    private func withTemporaryFile(
        contents: String,
        _ body: (String) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dualsense-profile-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("profile.json")
        try Data(contents.utf8).write(to: file)
        try body(file.path)
    }

    @Test("a missing path falls back to the starter profile")
    func nilPathUsesStarterProfile() throws {
        #expect(try ProfileLoader().load(path: nil) == .starterTerminal)
    }

    @Test("a valid file is loaded and validated")
    func validFileIsLoaded() throws {
        let json = #"{"schemaVersion":1,"name":"loaded","bindings":{"cross":{"kind":"tap","keys":"return"}}}"#
        try withTemporaryFile(contents: json) { path in
            let profile = try ProfileLoader().load(path: path)
            #expect(profile.name == "loaded")
            #expect(profile.binding(for: .cross) == .tap(KeyStroke(key: .return)))
        }
    }

    @Test("a missing file is reported as unreadable rather than ignored")
    func missingFileIsReported() {
        let loader = ProfileLoader()
        #expect(throws: ProfileLoadError.self) {
            try loader.load(path: "/nonexistent/dualsense-bridge/profile.json")
        }
    }

    @Test("an invalid profile surfaces the validation reason")
    func invalidProfileSurfacesReason() throws {
        let json = #"{"schemaVersion":1,"name":"bad","bindings":{"cross":{"kind":"tap","keys":"ctrl+shift"}}}"#
        try withTemporaryFile(contents: json) { path in
            #expect(throws: ProfileLoadError.self) {
                try ProfileLoader().load(path: path)
            }
            do {
                _ = try ProfileLoader().load(path: path)
            } catch let error as ProfileLoadError {
                #expect(error.description.contains("only contains modifiers"))
            }
        }
    }

    @Test("malformed JSON is reported as a profile problem")
    func malformedJSONIsReported() throws {
        try withTemporaryFile(contents: "{ not json") { path in
            #expect(throws: ProfileLoadError.self) {
                try ProfileLoader().load(path: path)
            }
        }
    }

    @Test("the documented default profile location is a config path, not a repo path")
    func defaultProfileLocation() {
        #expect(ProfileLoader.defaultRelativePath == ".config/dualsense-bridge/profile.json")
    }
}
