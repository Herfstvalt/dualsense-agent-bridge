import Foundation

/// What a control does when it is pressed.
public enum ControllerBinding: Hashable, Sendable {
    /// Press the shortcut on button-down and release it on button-up. This is
    /// the shape Wispr Flow press-to-talk needs.
    case hold(KeyStroke)
    /// Hold the shortcut and emit native-style repeat events until button-up.
    /// This is intended for editing/navigation keys such as Backspace.
    case repeatWhileHeld(KeyStroke)
    /// Emit a complete key-down/key-up pair on button-down.
    case tap(KeyStroke)
    /// Emit several complete key-down/key-up pairs in order on button-down.
    ///
    /// This exists for prefix-key programs: tmux reads `control+b` and *then* the
    /// command key, so the two cannot be sent as one chord. It is deliberately
    /// only an ordered list — no delays, no nesting, no repeats — because the
    /// moment a binding can express timing it stops being a binding and becomes a
    /// macro language to maintain.
    case tapSequence([KeyStroke])

    /// Every shortcut this binding involves, in the order it is sent.
    public var strokes: [KeyStroke] {
        switch self {
        case .hold(let stroke), .repeatWhileHeld(let stroke), .tap(let stroke): [stroke]
        case .tapSequence(let strokes): strokes
        }
    }

    /// The shortcuts as stored and displayed, e.g. `control+b, n`.
    var strokeText: String {
        strokes.map(\.description).joined(separator: ", ")
    }

    var kindName: String {
        switch self {
        case .hold: "hold"
        case .repeatWhileHeld: "repeat"
        case .tap: "tap"
        case .tapSequence: "tapSequence"
        }
    }
}

/// Why a stored profile could not be accepted.
public enum ProfileValidationError: Error, Hashable, Sendable, CustomStringConvertible {
    case unsupportedSchemaVersion(found: Int, supported: ClosedRange<Int>)
    case unknownControl(String)
    case unknownBindingKind(control: String, kind: String)
    case invalidShortcut(control: String, text: String, reason: String)
    case emptyTapSequence(control: String)
    case invalidNavigation(reason: String)
    case emptyName

    public var description: String {
        switch self {
        case .unsupportedSchemaVersion(let found, let supported):
            let understood =
                supported.lowerBound == supported.upperBound
                ? "version \(supported.lowerBound)"
                : "versions \(supported.lowerBound) through \(supported.upperBound)"
            return """
                Profile schemaVersion \(found) is not supported by this build, \
                which understands \(understood).
                """
        case .unknownControl(let name):
            return #"Unknown controller control "\#(name)". Run "dualsense-bridge controls" to list supported names."#
        case .unknownBindingKind(let control, let kind):
            return #"Binding for "\#(control)" uses unknown kind "\#(kind)". Use "hold", "repeat", "tap", or "tapSequence"."#
        case .invalidShortcut(let control, let text, let reason):
            return #"Binding for "\#(control)" has an invalid shortcut "\#(text)". \#(reason)"#
        case .emptyTapSequence(let control):
            return #"Binding for "\#(control)" is an empty sequence. List shortcuts in order, such as "control+b, n"."#
        case .invalidNavigation(let reason):
            return reason
        case .emptyName:
            return "A profile needs a non-empty name."
        }
    }
}

/// A named, versioned set of control bindings and navigation settings.
public struct ControllerProfile: Hashable, Sendable {
    /// The version this build writes.
    public static let currentSchemaVersion = 3
    /// Every version this build can read.
    ///
    /// Version 1 is the S1 format: bindings only, no navigation section. It is
    /// still accepted and gets the default navigation settings, so upgrading the
    /// bridge never invalidates a profile a user already tuned.
    /// Version 3 adds explicit key-repeat bindings; versions 1 and 2 remain
    /// readable and ordinary hold/tap behavior is unchanged.
    public static let supportedSchemaVersions = 1...3

    public let schemaVersion: Int
    public let name: String
    public let bindings: [ControllerControl: ControllerBinding]
    /// Stick tuning. Always present in memory, whatever the file version was.
    public let navigation: NavigationSettings

    public init(
        schemaVersion: Int = ControllerProfile.currentSchemaVersion,
        name: String,
        bindings: [ControllerControl: ControllerBinding],
        navigation: NavigationSettings = .default
    ) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.bindings = bindings
        self.navigation = navigation
    }

    public func binding(for control: ControllerControl) -> ControllerBinding? {
        bindings[control]
    }

    /// Sorted, human-readable binding lines for CLI diagnostics.
    public var summaryLines: [String] {
        bindings
            .map { "\($0.key.rawValue) -> \($0.value.kindName) \($0.value.strokeText)" }
            .sorted()
    }

    /// Human-readable navigation lines for CLI diagnostics.
    public var navigationSummaryLines: [String] {
        navigation.summaryLines
    }

    /// The tmux prefix, pressed and released before each command key.
    private static let tmuxPrefix = KeyStroke(key: .b, modifiers: .control)

    /// The default terminal profile.
    ///
    /// `r3` holds the Wispr Flow toggle chord for the physical click. `cross`
    /// sends Enter, `circle` cancels with Escape, Square sends Backspace and
    /// repeats while held, D-pad Up/Down walk shell history, and D-pad
    /// Left/Right plus Options send the user's Command-Z/C/V shortcuts.
    ///
    /// The shoulders drive tmux through its prefix: `r1` and `l1` step between
    /// windows and `l3` opens the session list. Each is a sequence rather than a
    /// chord because tmux reads the prefix and the command key as two separate
    /// keystrokes.
    ///
    /// Triangle opens macOS Accessibility Shortcuts (`Option-Command-F5`), which
    /// provides the supported path to the on-screen Accessibility Keyboard. The
    /// DualSense mic button keeps its hardware mute; R2 and L2 belong to the left
    /// and right mouse buttons rather than keyboard routing.
    ///
    /// The right stick moves the pointer and the left stick scrolls, using the
    /// responsive pointer and gentler scroll defaults.
    public static let starterTerminal = ControllerProfile(
        name: "starter-terminal",
        bindings: [
            .r3: .hold(KeyStroke(key: .s, modifiers: .control)),
            .cross: .tap(KeyStroke(key: .return)),
            .circle: .tap(KeyStroke(key: .escape)),
            .square: .repeatWhileHeld(KeyStroke(key: .delete)),
            .triangle: .tap(KeyStroke(key: .f5, modifiers: [.option, .command])),
            .touchpadButton: .tap(KeyStroke(key: .grave, modifiers: .control)),
            .r1: .tapSequence([tmuxPrefix, KeyStroke(key: .n)]),
            .l1: .tapSequence([tmuxPrefix, KeyStroke(key: .p)]),
            .l3: .tapSequence([tmuxPrefix, KeyStroke(key: .s)]),
            .dpadUp: .tap(KeyStroke(key: .arrowUp)),
            .dpadDown: .tap(KeyStroke(key: .arrowDown)),
            .dpadLeft: .tap(KeyStroke(key: .z, modifiers: .command)),
            .dpadRight: .tap(KeyStroke(key: .c, modifiers: .command)),
            .options: .tap(KeyStroke(key: .v, modifiers: .command)),
        ]
    )
}

// MARK: - Storage

extension ControllerProfile {
    private struct StoredBinding: Codable {
        var kind: String
        var keys: String
    }

    /// One stick's stored tuning.
    ///
    /// Every field is optional so a hand-edited file may set only the one value
    /// a user is tuning and inherit the rest, which is the difference between a
    /// two-line experiment and copying the whole block correctly.
    private struct StoredAxis: Codable {
        var deadzone: Double?
        var responseExponent: Double?
        var speed: Double?
        var invertX: Bool?
        var invertY: Bool?

        init(_ settings: NavigationAxisSettings) {
            deadzone = settings.deadzone
            responseExponent = settings.responseExponent
            speed = settings.speed
            invertX = settings.invertX
            invertY = settings.invertY
        }

        /// Applies whatever was present on top of the defaults.
        func applied(to defaults: NavigationAxisSettings) -> NavigationAxisSettings {
            var settings = defaults
            if let deadzone { settings.deadzone = deadzone }
            if let responseExponent { settings.responseExponent = responseExponent }
            if let speed { settings.speed = speed }
            if let invertX { settings.invertX = invertX }
            if let invertY { settings.invertY = invertY }
            return settings
        }
    }

    private struct StoredNavigation: Codable {
        var pointer: StoredAxis?
        var scroll: StoredAxis?
        var tickInterval: Double?
        var maximumTickInterval: Double?

        init(_ settings: NavigationSettings) {
            pointer = StoredAxis(settings.pointer)
            scroll = StoredAxis(settings.scroll)
            tickInterval = settings.tickInterval
            maximumTickInterval = settings.maximumTickInterval
        }

        func applied(to defaults: NavigationSettings) -> NavigationSettings {
            var settings = defaults
            if let pointer { settings.pointer = pointer.applied(to: defaults.pointer) }
            if let scroll { settings.scroll = scroll.applied(to: defaults.scroll) }
            if let tickInterval { settings.tickInterval = tickInterval }
            if let maximumTickInterval { settings.maximumTickInterval = maximumTickInterval }
            return settings
        }
    }

    private struct StoredProfile: Codable {
        var schemaVersion: Int
        var name: String
        var bindings: [String: StoredBinding]
        /// Absent in every version 1 profile, which is why it is optional.
        var navigation: StoredNavigation?
    }

    /// Decodes and validates a stored profile.
    ///
    /// Validation is strict: unknown controls, unknown binding kinds,
    /// unparseable shortcuts, and out-of-range navigation values are refused
    /// rather than silently dropped, so a typo can never quietly disable an
    /// interrupt binding or hand the cursor an absurd speed.
    ///
    /// A version 1 file is upgraded in memory rather than rejected: the model is
    /// always the current schema, so nothing later has to ask which version a
    /// profile came from.
    public init(decodingJSON data: Data) throws {
        let stored = try JSONDecoder().decode(StoredProfile.self, from: data)

        guard Self.supportedSchemaVersions.contains(stored.schemaVersion) else {
            throw ProfileValidationError.unsupportedSchemaVersion(
                found: stored.schemaVersion,
                supported: Self.supportedSchemaVersions
            )
        }
        guard !stored.name.trimmingCharactersInASCIIWhitespace().isEmpty else {
            throw ProfileValidationError.emptyName
        }

        var bindings: [ControllerControl: ControllerBinding] = [:]
        for (controlName, storedBinding) in stored.bindings {
            guard let control = ControllerControl(rawValue: controlName) else {
                throw ProfileValidationError.unknownControl(controlName)
            }

            switch storedBinding.kind {
            case "hold":
                bindings[control] = .hold(try Self.parseStroke(storedBinding.keys, for: controlName))
            case "repeat":
                bindings[control] = .repeatWhileHeld(
                    try Self.parseStroke(storedBinding.keys, for: controlName)
                )
            case "tap":
                bindings[control] = .tap(try Self.parseStroke(storedBinding.keys, for: controlName))
            case "tapSequence":
                bindings[control] = .tapSequence(
                    try Self.parseSequence(storedBinding.keys, for: controlName)
                )
            default:
                throw ProfileValidationError.unknownBindingKind(
                    control: controlName,
                    kind: storedBinding.kind
                )
            }
        }

        let navigation = stored.navigation?.applied(to: .default) ?? .default
        do {
            try navigation.validate()
        } catch let error as NavigationSettingsError {
            throw ProfileValidationError.invalidNavigation(reason: error.description)
        }

        self.init(
            schemaVersion: Self.currentSchemaVersion,
            name: stored.name,
            bindings: bindings,
            navigation: navigation
        )
    }

    /// Parses one shortcut, reporting which control the bad text came from.
    ///
    /// The control name is what makes the message actionable: `"nope" is not a
    /// key` sends a user hunting through the file, while naming `r1` does not.
    private static func parseStroke(_ text: String, for control: String) throws -> KeyStroke {
        do {
            return try KeyStroke(parsing: text)
        } catch let error as KeyStrokeParseError {
            throw ProfileValidationError.invalidShortcut(
                control: control,
                text: text,
                reason: error.description
            )
        }
    }

    /// Parses an ordered, comma-separated list of shortcuts.
    ///
    /// Comma is unambiguous as the separator because shortcuts join their parts
    /// with `+` and every key is named in words, so the comma key itself is
    /// spelled `comma` and survives a round trip.
    private static func parseSequence(_ text: String, for control: String) throws -> [KeyStroke] {
        let parts = text
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharactersInASCIIWhitespace() }

        // An empty sequence would be a binding that silently does nothing, which
        // is exactly the failure mode strict validation exists to prevent.
        guard parts.contains(where: { !$0.isEmpty }) else {
            throw ProfileValidationError.emptyTapSequence(control: control)
        }
        guard !parts.contains(where: \.isEmpty) else {
            throw ProfileValidationError.invalidShortcut(
                control: control,
                text: "",
                reason: "A tap sequence cannot contain an empty shortcut."
            )
        }
        return try parts.map { try parseStroke($0, for: control) }
    }

    /// Encodes the profile as stable, human-editable JSON.
    ///
    /// Always written in the current schema version with the navigation section
    /// spelled out in full, so the file a user edits shows every value that is
    /// actually in effect rather than hiding defaults.
    public func encodedJSON() throws -> Data {
        let stored = StoredProfile(
            schemaVersion: Self.currentSchemaVersion,
            name: name,
            bindings: Dictionary(
                uniqueKeysWithValues: bindings.map { control, binding in
                    (control.rawValue, StoredBinding(kind: binding.kindName, keys: binding.strokeText))
                }
            ),
            navigation: StoredNavigation(navigation)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(stored)
    }
}
