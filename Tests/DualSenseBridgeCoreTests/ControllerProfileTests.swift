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
    @Test("the starter profile binds Wispr hold, Enter, Escape, and the Wispr toggle")
    func starterProfileBindings() throws {
        let profile = ControllerProfile.starterTerminal

        #expect(profile.schemaVersion == ControllerProfile.currentSchemaVersion)
        #expect(profile.binding(for: .l2) == .hold(try KeyStroke(parsing: "control+option+space")))
        #expect(profile.binding(for: .cross) == .tap(KeyStroke(key: .return)))
        #expect(profile.binding(for: .circle) == .tap(KeyStroke(key: .escape)))
        #expect(profile.binding(for: .r3) == .tap(KeyStroke(key: .s, modifiers: .control)))
    }

    @Test("the starter profile drives tmux windows and sessions from the shoulders")
    func starterProfileTmuxBindings() {
        let profile = ControllerProfile.starterTerminal
        let prefix = KeyStroke(key: .b, modifiers: .control)

        #expect(profile.binding(for: .r1) == .tapSequence([prefix, KeyStroke(key: .n)]))
        #expect(profile.binding(for: .l1) == .tapSequence([prefix, KeyStroke(key: .p)]))
        #expect(profile.binding(for: .l3) == .tapSequence([prefix, KeyStroke(key: .s)]))
    }

    @Test("the starter profile maps the touchpad click and the D-pad")
    func starterProfileTouchpadAndDpad() {
        let profile = ControllerProfile.starterTerminal

        #expect(profile.binding(for: .touchpadButton) == .tap(KeyStroke(key: .grave, modifiers: .control)))
        #expect(profile.binding(for: .dpadUp) == .tap(KeyStroke(key: .arrowUp)))
        #expect(profile.binding(for: .dpadDown) == .tap(KeyStroke(key: .arrowDown)))
    }

    @Test("the starter profile leaves the mic button, Square, and Triangle alone")
    func reservedControlsAreUnbound() {
        let profile = ControllerProfile.starterTerminal

        // The mic button keeps its hardware mute; Square and Triangle are left
        // free on purpose so there is somewhere obvious to add a personal binding.
        #expect(profile.binding(for: .micButton) == nil)
        #expect(profile.binding(for: .square) == nil)
        #expect(profile.binding(for: .triangle) == nil)
    }

    @Test("the starter profile binds exactly the controls the map names")
    func starterProfileBindsNothingElse() {
        let bound = Set(ControllerProfile.starterTerminal.bindings.keys)

        // R2 is absent because the pointer owns it, not the keyboard.
        #expect(
            bound == [
                .l2, .cross, .circle, .r3, .r1, .l1, .l3,
                .touchpadButton, .dpadUp, .dpadDown,
            ]
        )
    }

    @Test("the whole starter profile round-trips through its own file format")
    func starterProfileRoundTrips() throws {
        let decoded = try ControllerProfile(
            decodingJSON: try ControllerProfile.starterTerminal.encodedJSON()
        )

        #expect(decoded == ControllerProfile.starterTerminal)
    }

    @Test("the starter profile binds no destructive action")
    func noDestructiveBindings() {
        // Flattened, so every step of a tap sequence is checked and not just its
        // first keystroke.
        let strokes = ControllerProfile.starterTerminal.bindings.values.flatMap(\.strokes)
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
        #expect(
            throws: ProfileValidationError.unsupportedSchemaVersion(
                found: 99,
                supported: ControllerProfile.supportedSchemaVersions
            )
        ) {
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
            ProfileValidationError.unsupportedSchemaVersion(found: 99, supported: 1...2).description
                == "Profile schemaVersion 99 is not supported by this build, which understands versions 1 through 2."
        )
        #expect(
            ProfileValidationError.unsupportedSchemaVersion(found: 99, supported: 1...1).description
                == "Profile schemaVersion 99 is not supported by this build, which understands version 1."
        )
        #expect(
            ProfileValidationError.unknownBindingKind(control: "cross", kind: "toggle").description
                == #"Binding for "cross" uses unknown kind "toggle". Use "hold", "tap", or "tapSequence"."#
        )
    }

    @Test("a profile summary describes bindings for diagnostics")
    func profileSummary() {
        let summary = ControllerProfile.starterTerminal.summaryLines
        #expect(summary.contains("cross -> tap return"))
        #expect(summary.contains("l2 -> hold control+option+space"))
        #expect(summary.contains("r3 -> tap control+s"))
        // A sequence has to be readable here too, or the CLI cannot explain what
        // a shoulder button will actually send.
        #expect(summary.contains("r1 -> tapSequence control+b, n"))
        #expect(summary == summary.sorted())
    }
}
