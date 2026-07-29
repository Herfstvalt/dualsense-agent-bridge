import Foundation

/// What a control does when it is pressed.
public enum ControllerBinding: Hashable, Sendable {
    /// Press the shortcut on button-down and release it on button-up. This is
    /// the shape Wispr Flow press-to-talk needs.
    case hold(KeyStroke)
    /// Emit a complete key-down/key-up pair on button-down.
    case tap(KeyStroke)

    public var stroke: KeyStroke {
        switch self {
        case .hold(let stroke), .tap(let stroke): stroke
        }
    }

    var kindName: String {
        switch self {
        case .hold: "hold"
        case .tap: "tap"
        }
    }
}

/// Why a stored profile could not be accepted.
public enum ProfileValidationError: Error, Hashable, Sendable, CustomStringConvertible {
    case unsupportedSchemaVersion(found: Int, supported: Int)
    case unknownControl(String)
    case unknownBindingKind(control: String, kind: String)
    case invalidShortcut(control: String, text: String, reason: String)
    case emptyName

    public var description: String {
        switch self {
        case .unsupportedSchemaVersion(let found, let supported):
            return """
                Profile schemaVersion \(found) is not supported by this build, \
                which understands version \(supported).
                """
        case .unknownControl(let name):
            return #"Unknown controller control "\#(name)". Run "dualsense-bridge controls" to list supported names."#
        case .unknownBindingKind(let control, let kind):
            return #"Binding for "\#(control)" uses unknown kind "\#(kind)". Use "hold" or "tap"."#
        case .invalidShortcut(let control, let text, let reason):
            return #"Binding for "\#(control)" has an invalid shortcut "\#(text)". \#(reason)"#
        case .emptyName:
            return "A profile needs a non-empty name."
        }
    }
}

/// A named, versioned set of control bindings.
public struct ControllerProfile: Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let name: String
    public let bindings: [ControllerControl: ControllerBinding]

    public init(
        schemaVersion: Int = ControllerProfile.currentSchemaVersion,
        name: String,
        bindings: [ControllerControl: ControllerBinding]
    ) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.bindings = bindings
    }

    public func binding(for control: ControllerControl) -> ControllerBinding? {
        bindings[control]
    }

    /// Sorted, human-readable binding lines for CLI diagnostics.
    public var summaryLines: [String] {
        bindings
            .map { "\($0.key.rawValue) -> \($0.value.kindName) \($0.value.stroke)" }
            .sorted()
    }

    /// The default terminal profile.
    ///
    /// `l2` holds the Wispr Flow shortcut, `cross` sends Enter, `circle`
    /// cancels with Escape, and `r3` interrupts with Ctrl-C. The DualSense mic
    /// button is deliberately left unbound so it keeps its hardware behavior.
    public static let starterTerminal = ControllerProfile(
        name: "starter-terminal",
        bindings: [
            .l2: .hold(KeyStroke(key: .space, modifiers: [.control, .option])),
            .cross: .tap(KeyStroke(key: .return)),
            .circle: .tap(KeyStroke(key: .escape)),
            .r3: .tap(KeyStroke(key: .c, modifiers: .control)),
        ]
    )
}

// MARK: - Storage

extension ControllerProfile {
    private struct StoredBinding: Codable {
        var kind: String
        var keys: String
    }

    private struct StoredProfile: Codable {
        var schemaVersion: Int
        var name: String
        var bindings: [String: StoredBinding]
    }

    /// Decodes and validates a stored profile.
    ///
    /// Validation is strict: unknown controls, unknown binding kinds, and
    /// unparseable shortcuts are refused rather than silently dropped, so a
    /// typo can never quietly disable an interrupt binding.
    public init(decodingJSON data: Data) throws {
        let stored = try JSONDecoder().decode(StoredProfile.self, from: data)

        guard stored.schemaVersion == Self.currentSchemaVersion else {
            throw ProfileValidationError.unsupportedSchemaVersion(
                found: stored.schemaVersion,
                supported: Self.currentSchemaVersion
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

            let stroke: KeyStroke
            do {
                stroke = try KeyStroke(parsing: storedBinding.keys)
            } catch let error as KeyStrokeParseError {
                throw ProfileValidationError.invalidShortcut(
                    control: controlName,
                    text: storedBinding.keys,
                    reason: error.description
                )
            }

            switch storedBinding.kind {
            case "hold": bindings[control] = .hold(stroke)
            case "tap": bindings[control] = .tap(stroke)
            default:
                throw ProfileValidationError.unknownBindingKind(
                    control: controlName,
                    kind: storedBinding.kind
                )
            }
        }

        self.init(schemaVersion: stored.schemaVersion, name: stored.name, bindings: bindings)
    }

    /// Encodes the profile as stable, human-editable JSON.
    public func encodedJSON() throws -> Data {
        let stored = StoredProfile(
            schemaVersion: schemaVersion,
            name: name,
            bindings: Dictionary(
                uniqueKeysWithValues: bindings.map { control, binding in
                    (control.rawValue, StoredBinding(kind: binding.kindName, keys: binding.stroke.description))
                }
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(stored)
    }
}
