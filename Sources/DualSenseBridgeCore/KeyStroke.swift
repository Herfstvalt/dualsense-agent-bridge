/// A physical key on a macOS keyboard, identified independently of any
/// particular event framework.
///
/// Modifier keys are ordinary members because press-to-talk shortcuts must be
/// held down and released as individual physical keys; that is what makes
/// held-key cleanup possible after a controller disconnects mid-chord.
public enum KeyCode: String, Codable, CaseIterable, Hashable, Sendable {
    case a, b, c, d, e, f, g, h, i, j, k, l, m
    case n, o, p, q, r, s, t, u, v, w, x, y, z
    case zero, one, two, three, four, five, six, seven, eight, nine
    case `return`, escape, space, tab, delete, forwardDelete
    case arrowLeft, arrowRight, arrowUp, arrowDown
    case home, end, pageUp, pageDown
    case minus, equal, leftBracket, rightBracket, backslash
    case semicolon, quote, comma, period, slash, grave
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    case control, option, shift, command

    /// The macOS virtual key code (`kVK_*`) for this key.
    public var virtualKeyCode: UInt16 {
        switch self {
        case .a: 0x00
        case .s: 0x01
        case .d: 0x02
        case .f: 0x03
        case .h: 0x04
        case .g: 0x05
        case .z: 0x06
        case .x: 0x07
        case .c: 0x08
        case .v: 0x09
        case .b: 0x0B
        case .q: 0x0C
        case .w: 0x0D
        case .e: 0x0E
        case .r: 0x0F
        case .y: 0x10
        case .t: 0x11
        case .one: 0x12
        case .two: 0x13
        case .three: 0x14
        case .four: 0x15
        case .six: 0x16
        case .five: 0x17
        case .equal: 0x18
        case .nine: 0x19
        case .seven: 0x1A
        case .minus: 0x1B
        case .eight: 0x1C
        case .zero: 0x1D
        case .rightBracket: 0x1E
        case .o: 0x1F
        case .u: 0x20
        case .leftBracket: 0x21
        case .i: 0x22
        case .p: 0x23
        case .return: 0x24
        case .l: 0x25
        case .j: 0x26
        case .quote: 0x27
        case .k: 0x28
        case .semicolon: 0x29
        case .backslash: 0x2A
        case .comma: 0x2B
        case .slash: 0x2C
        case .n: 0x2D
        case .m: 0x2E
        case .period: 0x2F
        case .tab: 0x30
        case .space: 0x31
        case .grave: 0x32
        case .delete: 0x33
        case .escape: 0x35
        case .command: 0x37
        case .shift: 0x38
        case .option: 0x3A
        case .control: 0x3B
        case .f5: 0x60
        case .f6: 0x61
        case .f7: 0x62
        case .f3: 0x63
        case .f8: 0x64
        case .f9: 0x65
        case .f11: 0x67
        case .f10: 0x6D
        case .f12: 0x6F
        case .home: 0x73
        case .pageUp: 0x74
        case .forwardDelete: 0x75
        case .f4: 0x76
        case .end: 0x77
        case .f2: 0x78
        case .pageDown: 0x79
        case .f1: 0x7A
        case .arrowLeft: 0x7B
        case .arrowRight: 0x7C
        case .arrowDown: 0x7D
        case .arrowUp: 0x7E
        }
    }

    /// The modifier this key toggles, when the key is a modifier key.
    public var modifier: KeyModifiers? {
        switch self {
        case .control: .control
        case .option: .option
        case .shift: .shift
        case .command: .command
        default: nil
        }
    }

    /// The canonical name used in configuration files and diagnostics.
    public var canonicalName: String {
        switch self {
        case .zero: "0"
        case .one: "1"
        case .two: "2"
        case .three: "3"
        case .four: "4"
        case .five: "5"
        case .six: "6"
        case .seven: "7"
        case .eight: "8"
        case .nine: "9"
        default: rawValue
        }
    }
}

/// The chord modifiers that can accompany a base key.
public struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let control = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let shift = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)

    /// Modifier keys in the order they should be pressed, so that the base key
    /// is always delivered with the full chord already active.
    static let pressOrder: [(KeyModifiers, KeyCode)] = [
        (.control, .control),
        (.option, .option),
        (.shift, .shift),
        (.command, .command),
    ]

    var physicalKeys: [KeyCode] {
        Self.pressOrder.filter { contains($0.0) }.map(\.1)
    }

    var canonicalNames: [String] {
        physicalKeys.map(\.canonicalName)
    }
}

/// A modifier chord plus a single base key, as configured by the user.
public struct KeyStroke: Hashable, Sendable, CustomStringConvertible {
    public let key: KeyCode
    public let modifiers: KeyModifiers

    public init(key: KeyCode, modifiers: KeyModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Physical keys in the order they must be pressed down.
    public var physicalKeysInPressOrder: [KeyCode] {
        modifiers.physicalKeys + [key]
    }

    /// Physical keys in the order they must be released, mirroring the press
    /// order so a chord never leaves a modifier latched.
    public var physicalKeysInReleaseOrder: [KeyCode] {
        physicalKeysInPressOrder.reversed()
    }

    public var description: String {
        (modifiers.canonicalNames + [key.canonicalName]).joined(separator: "+")
    }
}

// MARK: - Parsing

/// Why a configured shortcut could not be understood.
public enum KeyStrokeParseError: Error, Hashable, Sendable, CustomStringConvertible {
    case empty
    case unknownToken(String)
    case unsupportedModifier(String)
    case missingBaseKey(String)
    case multipleBaseKeys(String)

    public var description: String {
        switch self {
        case .empty:
            return "A shortcut cannot be empty. Use text such as control+option+space."
        case .unknownToken(let token):
            return """
                Unknown key or modifier "\(token)". Use names such as control, \
                option, shift, command, return, escape, space, or a single letter.
                """
        case .unsupportedModifier(let token):
            return """
                The "\(token)" modifier cannot be emitted as a synthetic key. \
                Choose a shortcut built from control, option, shift, or command.
                """
        case .missingBaseKey(let text):
            return #"Shortcut "\#(text)" only contains modifiers. Add a key such as space."#
        case .multipleBaseKeys(let text):
            return #"Shortcut "\#(text)" names more than one base key. Use a single key with modifiers."#
        }
    }
}

extension KeyStroke {
    private static let modifierAliases: [String: KeyModifiers] = [
        "control": .control, "ctrl": .control, "ctl": .control,
        "option": .option, "opt": .option, "alt": .option,
        "shift": .shift,
        "command": .command, "cmd": .command, "meta": .command, "super": .command,
    ]

    /// Modifiers that macOS will not accept from a synthetic event source.
    private static let unsupportedModifiers: Set<String> = ["fn", "function", "globe"]

    private static let keyAliases: [String: KeyCode] = {
        var aliases: [String: KeyCode] = [:]
        // Lowercased on the way in, because parsing lowercases its tokens. Without
        // this every camelCase name the encoder writes -- `arrowUp`,
        // `forwardDelete`, `pageDown` -- parsed as an unknown key, so a profile
        // this build had just written could not be read back.
        for key in KeyCode.allCases where key.modifier == nil {
            aliases[key.rawValue.lowercased()] = key
            aliases[key.canonicalName.lowercased()] = key
        }
        aliases["enter"] = .return
        aliases["esc"] = .escape
        aliases["backspace"] = .delete
        aliases["del"] = .forwardDelete
        aliases["spacebar"] = .space
        aliases["left"] = .arrowLeft
        aliases["right"] = .arrowRight
        aliases["up"] = .arrowUp
        aliases["down"] = .arrowDown
        aliases["pgup"] = .pageUp
        aliases["pgdn"] = .pageDown
        aliases["pagedown"] = .pageDown
        aliases["pageup"] = .pageUp
        aliases["backtick"] = .grave
        return aliases
    }()

    /// Parses user-facing configuration text such as `control+option+space`.
    ///
    /// Parsing keeps the Wispr Flow shortcut changeable without recompiling.
    public init(parsing text: String) throws {
        let tokens = text
            .split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharactersInASCIIWhitespace().lowercased() }
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { throw KeyStrokeParseError.empty }

        var modifiers: KeyModifiers = []
        var baseKey: KeyCode?

        for token in tokens {
            if let modifier = Self.modifierAliases[token] {
                modifiers.insert(modifier)
            } else if Self.unsupportedModifiers.contains(token) {
                throw KeyStrokeParseError.unsupportedModifier(token)
            } else if let key = Self.keyAliases[token] {
                guard baseKey == nil else {
                    throw KeyStrokeParseError.multipleBaseKeys(text)
                }
                baseKey = key
            } else {
                throw KeyStrokeParseError.unknownToken(token)
            }
        }

        guard let baseKey else {
            throw KeyStrokeParseError.missingBaseKey(text)
        }

        self.init(key: baseKey, modifiers: modifiers)
    }
}

// MARK: - Codable

extension KeyStroke: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        do {
            try self.init(parsing: text)
        } catch let error as KeyStrokeParseError {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: error.description)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

extension StringProtocol {
    /// Trims ASCII whitespace without pulling in Foundation character sets.
    func trimmingCharactersInASCIIWhitespace() -> String {
        let whitespace: Set<Character> = [" ", "\t", "\n", "\r"]
        var characters = Array(self)
        while let first = characters.first, whitespace.contains(first) {
            characters.removeFirst()
        }
        while let last = characters.last, whitespace.contains(last) {
            characters.removeLast()
        }
        return String(characters)
    }
}
