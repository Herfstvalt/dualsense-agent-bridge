import Foundation
import Testing

@testable import DualSenseBridgeCore

@Suite("the controller event model stays independent of input frameworks")
struct ControllerEventTests {
    @Test("a button event records control, phase, timestamp, and source")
    func buttonEventCarriesContext() {
        let controller = ControllerIdentity(id: "controller-1", displayName: "DualSense")
        let event = ControllerEvent(
            controller: controller,
            control: .cross,
            phase: .pressed,
            timestamp: 12.5,
            source: .fake
        )

        #expect(event.control == .cross)
        #expect(event.phase == .pressed)
        #expect(event.timestamp == 12.5)
        #expect(event.source == .fake)
        #expect(event.controller == controller)
    }

    @Test("disconnect is part of the input stream rather than a side channel")
    func disconnectIsAnInput() {
        let controller = ControllerIdentity(id: "controller-1", displayName: "DualSense")
        let inputs: [ControllerInput] = [
            .connected(controller),
            .disconnected(controller),
            .shutdown,
        ]

        #expect(inputs.compactMap(\.controller) == [controller, controller])
        #expect(inputs.last == .shutdown)
    }

    @Test("controls are named in configuration-friendly text")
    func controlNames() {
        #expect(ControllerControl.cross.rawValue == "cross")
        #expect(ControllerControl.r3.rawValue == "r3")
        #expect(ControllerControl.dpadLeft.rawValue == "dpadLeft")
        #expect(ControllerControl.allCases.contains(.micButton))
    }

    @Test("a released phase is the inverse of a pressed phase")
    func phaseInversion() {
        #expect(ControllerEventPhase.pressed.isPressed)
        #expect(!ControllerEventPhase.released.isPressed)
    }
}

@Suite("profiles are versioned, validated, and safe by default")
struct ControllerProfileTests {
    @Test("the starter profile binds Wispr hold, Enter, Escape, and interrupt")
    func starterProfileBindings() throws {
        let profile = ControllerProfile.starterTerminal

        #expect(profile.schemaVersion == ControllerProfile.currentSchemaVersion)
        #expect(profile.binding(for: .l2) == .hold(try KeyStroke(parsing: "control+option+space")))
        #expect(profile.binding(for: .cross) == .tap(KeyStroke(key: .return)))
        #expect(profile.binding(for: .circle) == .tap(KeyStroke(key: .escape)))
        #expect(profile.binding(for: .r3) == .tap(KeyStroke(key: .c, modifiers: .control)))
    }

    @Test("the starter profile leaves the controller mic button alone")
    func micButtonIsUnbound() {
        #expect(ControllerProfile.starterTerminal.binding(for: .micButton) == nil)
    }

    @Test("the starter profile binds no destructive action")
    func noDestructiveBindings() {
        let strokes = ControllerProfile.starterTerminal.bindings.values.map(\.stroke)
        #expect(!strokes.contains(where: { $0.modifiers.contains(.command) }))
        #expect(strokes.allSatisfy { $0.key != .delete && $0.key != .forwardDelete })
    }

    @Test("the push-to-talk shortcut can be replaced without recompiling")
    func pushToTalkShortcutIsConfigurable() throws {
        let json = """
            {
              "schemaVersion": 1,
              "name": "custom",
              "bindings": {
                "r1": { "kind": "hold", "keys": "cmd+shift+d" },
                "cross": { "kind": "tap", "keys": "return" }
              }
            }
            """
        let profile = try ControllerProfile(decodingJSON: Data(json.utf8))

        #expect(profile.name == "custom")
        #expect(profile.binding(for: .r1) == .hold(KeyStroke(key: .d, modifiers: [.command, .shift])))
        #expect(profile.binding(for: .l2) == nil)
    }

    @Test("a profile round-trips through JSON as a keyed object")
    func profileRoundTrip() throws {
        let encoded = try ControllerProfile.starterTerminal.encodedJSON()
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(text.contains(#""cross""#))
        #expect(text.contains(#""control+option+space""#))
        #expect(try ControllerProfile(decodingJSON: encoded) == ControllerProfile.starterTerminal)
    }

    @Test("an unknown schema version is refused instead of guessed")
    func unknownSchemaVersionIsRefused() {
        let json = #"{"schemaVersion": 99, "name": "x", "bindings": {}}"#
        #expect(throws: ProfileValidationError.unsupportedSchemaVersion(found: 99, supported: 1)) {
            try ControllerProfile(decodingJSON: Data(json.utf8))
        }
    }

    @Test("an unknown control name is refused and named")
    func unknownControlIsRefused() {
        let json = #"{"schemaVersion": 1, "name": "x", "bindings": {"triangleish": {"kind":"tap","keys":"return"}}}"#
        #expect(throws: ProfileValidationError.unknownControl("triangleish")) {
            try ControllerProfile(decodingJSON: Data(json.utf8))
        }
    }

    @Test("an unknown binding kind is refused and named")
    func unknownBindingKindIsRefused() {
        let json = #"{"schemaVersion": 1, "name": "x", "bindings": {"cross": {"kind":"toggle","keys":"return"}}}"#
        #expect(throws: ProfileValidationError.unknownBindingKind(control: "cross", kind: "toggle")) {
            try ControllerProfile(decodingJSON: Data(json.utf8))
        }
    }

    @Test("an invalid shortcut is refused with the underlying reason")
    func invalidShortcutIsRefused() {
        let json = #"{"schemaVersion": 1, "name": "x", "bindings": {"cross": {"kind":"tap","keys":"ctrl+shift"}}}"#
        #expect(
            throws: ProfileValidationError.invalidShortcut(
                control: "cross",
                text: "ctrl+shift",
                reason: KeyStrokeParseError.missingBaseKey("ctrl+shift").description
            )
        ) {
            try ControllerProfile(decodingJSON: Data(json.utf8))
        }
    }

    @Test("validation errors read as guidance a user can act on")
    func validationErrorsAreReadable() {
        #expect(
            ProfileValidationError.unknownControl("triangleish").description
                == #"Unknown controller control "triangleish". Run "dualsense-bridge controls" to list supported names."#
        )
        #expect(
            ProfileValidationError.unsupportedSchemaVersion(found: 99, supported: 1).description
                == "Profile schemaVersion 99 is not supported by this build, which understands version 1."
        )
    }

    @Test("a profile summary describes bindings for diagnostics")
    func profileSummary() {
        let summary = ControllerProfile.starterTerminal.summaryLines
        #expect(summary.contains("cross -> tap return"))
        #expect(summary.contains("l2 -> hold control+option+space"))
        #expect(summary.contains("r3 -> tap control+c"))
        #expect(summary == summary.sorted())
    }
}
