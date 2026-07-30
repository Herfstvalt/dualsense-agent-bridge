import Foundation
import Testing

@testable import DualSenseBridgeCore

@Suite("keystrokes are described by configuration text")
struct KeyStrokeTests {
    @Test("a bare key name parses without modifiers")
    func bareKeyName() throws {
        let stroke = try KeyStroke(parsing: "return")
        #expect(stroke.key == .return)
        #expect(stroke.modifiers.isEmpty)
    }

    @Test("modifier aliases resolve to the same stroke")
    func modifierAliases() throws {
        let canonical = try KeyStroke(parsing: "control+option+space")
        #expect(try KeyStroke(parsing: "ctrl+alt+space") == canonical)
        #expect(try KeyStroke(parsing: "CTRL + ALT + SPACE") == canonical)
        #expect(try KeyStroke(parsing: "option+control+space") == canonical)
    }

    @Test("key aliases resolve to the same stroke")
    func keyAliases() throws {
        #expect(try KeyStroke(parsing: "enter") == KeyStroke(key: .return))
        #expect(try KeyStroke(parsing: "esc") == KeyStroke(key: .escape))
        #expect(try KeyStroke(parsing: "backspace") == KeyStroke(key: .delete))
    }

    @Test("the description is canonical and round-trips")
    func canonicalDescription() throws {
        let stroke = try KeyStroke(parsing: "cmd+shift+alt+ctrl+k")
        #expect(stroke.description == "control+option+shift+command+k")
        #expect(try KeyStroke(parsing: stroke.description) == stroke)
    }

    @Test("every key name this build writes can be read back")
    func everyKeyNameRoundTrips() throws {
        // Parsing lowercases its tokens, so a camelCase name such as `arrowUp`
        // silently failed to parse even though that is exactly what the encoder
        // writes, which made an arrow-key binding unloadable.
        for key in KeyCode.allCases where key.modifier == nil {
            let stroke = KeyStroke(key: key)
            #expect(try KeyStroke(parsing: stroke.description) == stroke)
        }
    }

    @Test("key names are accepted whatever case they are written in")
    func keyNamesAreCaseInsensitive() throws {
        #expect(try KeyStroke(parsing: "ARROWUP") == KeyStroke(key: .arrowUp))
        #expect(try KeyStroke(parsing: "arrowup") == KeyStroke(key: .arrowUp))
        #expect(try KeyStroke(parsing: "arrowUp") == KeyStroke(key: .arrowUp))
        #expect(try KeyStroke(parsing: "control+PageDown") == KeyStroke(key: .pageDown, modifiers: .control))
    }

    @Test("interrupt is expressed as control and the letter c")
    func interruptStroke() throws {
        let stroke = try KeyStroke(parsing: "ctrl+c")
        #expect(stroke == KeyStroke(key: .c, modifiers: .control))
        #expect(stroke.description == "control+c")
    }

    @Test("modifiers are pressed before the base key and released in reverse")
    func physicalKeyOrder() throws {
        let stroke = try KeyStroke(parsing: "cmd+shift+space")
        #expect(stroke.physicalKeysInPressOrder == [.shift, .command, .space])
        #expect(stroke.physicalKeysInReleaseOrder == [.space, .command, .shift])
    }

    @Test("a stroke without modifiers still reports its physical key")
    func physicalKeyWithoutModifiers() {
        let stroke = KeyStroke(key: .escape)
        #expect(stroke.physicalKeysInPressOrder == [.escape])
    }

    @Test("empty configuration text is rejected")
    func emptyTextIsRejected() {
        #expect(throws: KeyStrokeParseError.empty) {
            try KeyStroke(parsing: "   ")
        }
    }

    @Test("a modifier-only shortcut is rejected because it cannot be tapped")
    func modifierOnlyIsRejected() {
        #expect(throws: KeyStrokeParseError.missingBaseKey("control+shift")) {
            try KeyStroke(parsing: "control+shift")
        }
    }

    @Test("two base keys are rejected instead of silently dropping one")
    func multipleBaseKeysAreRejected() {
        #expect(throws: KeyStrokeParseError.multipleBaseKeys("control+a+b")) {
            try KeyStroke(parsing: "control+a+b")
        }
    }

    @Test("an unknown token names itself in the error")
    func unknownTokenIsNamed() {
        #expect(throws: KeyStrokeParseError.unknownToken("hyper")) {
            try KeyStroke(parsing: "hyper+space")
        }
    }

    @Test("the unsupported fn modifier is rejected with an explanation")
    func functionModifierIsRejected() {
        #expect(throws: KeyStrokeParseError.unsupportedModifier("fn")) {
            try KeyStroke(parsing: "fn+space")
        }
    }

    @Test("parse errors read as guidance a user can act on")
    func parseErrorsAreReadable() {
        #expect(
            KeyStrokeParseError.unknownToken("hyper").description
                == #"Unknown key or modifier "hyper". Use names such as control, option, shift, command, return, escape, space, or a single letter."#
        )
        #expect(
            KeyStrokeParseError.unsupportedModifier("fn").description
                == #"The "fn" modifier cannot be emitted as a synthetic key. Choose a shortcut built from control, option, shift, or command."#
        )
        #expect(
            KeyStrokeParseError.missingBaseKey("control+shift").description
                == #"Shortcut "control+shift" only contains modifiers. Add a key such as space."#
        )
    }

    @Test("every key code maps to a distinct macOS virtual key code")
    func virtualKeyCodesAreDistinct() {
        let codes = KeyCode.allCases.map(\.virtualKeyCode)
        #expect(Set(codes).count == codes.count)
    }

    @Test("a stroke encodes to configuration text as a single JSON string")
    func codableRoundTrip() throws {
        let stroke = try KeyStroke(parsing: "ctrl+alt+space")
        let data = try JSONEncoder().encode(stroke)
        #expect(String(decoding: data, as: UTF8.self) == #""control+option+space""#)
        #expect(try JSONDecoder().decode(KeyStroke.self, from: data) == stroke)
    }

    @Test("decoding invalid configuration text fails instead of defaulting")
    func codableRejectsInvalidText() {
        let data = Data(#""hyper+space""#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(KeyStroke.self, from: data)
        }
    }
}
