import Foundation
import Testing

@testable import DualSenseBridgeCore

@Suite("a tap sequence sends ordered keystrokes, each fully released before the next")
struct TapSequenceTests {
    private let controlB = KeyStroke(key: .b, modifiers: .control)

    // MARK: - Routing

    @Test("a tap sequence routes to one tap per stroke, in order")
    func routesOneTapPerStroke() {
        var input = FakeControllerInput()
        var router = ActionRouter(
            profile: ControllerProfile(
                name: "test",
                bindings: [.r1: .tapSequence([controlB, KeyStroke(key: .n)])]
            )
        )

        #expect(
            router.handle(input.press(.r1)) == [
                .tap(controlB),
                .tap(KeyStroke(key: .n)),
            ]
        )
        // A sequence fires on press only, exactly like an ordinary tap.
        #expect(router.handle(input.release(.r1)).isEmpty)
    }

    @Test("Control-B is fully released before the next key is pressed")
    func eachStrokeIsReleasedBeforeTheNext() {
        var input = FakeControllerInput()
        let keys = RecordingKeyboardSink()
        let bridge = ControllerBridge(
            profile: ControllerProfile(
                name: "test",
                bindings: [.r1: .tapSequence([controlB, KeyStroke(key: .n)])]
            ),
            keyboard: SyntheticKeyboard(sink: keys, accessibility: .fixed(.granted))
        )

        bridge.handle(input.press(.r1))

        // This is the whole reason a sequence is not a chord: tmux reads its
        // prefix and then the command key, so control must be up before `n`.
        #expect(
            keys.transcript == [
                "down control",
                "down b",
                "up b",
                "up control",
                "down n",
                "up n",
            ]
        )
        #expect(bridge.heldKeys.isEmpty)
    }

    @Test("a sequence emits nothing at all without Accessibility permission")
    func refusedWithoutPermission() {
        var input = FakeControllerInput()
        let keys = RecordingKeyboardSink()
        let bridge = ControllerBridge(
            profile: ControllerProfile(
                name: "test",
                bindings: [.r1: .tapSequence([controlB, KeyStroke(key: .n)])]
            ),
            keyboard: SyntheticKeyboard(sink: keys, accessibility: .fixed(.denied))
        )

        let steps = bridge.handle(input.press(.r1))

        #expect(steps.count == 2)
        #expect(steps.allSatisfy { $0.outcome.isRefusal })
        #expect(keys.emissions.isEmpty)
    }

    @Test("a single-stroke sequence behaves exactly like a tap")
    func singleStrokeSequence() {
        var input = FakeControllerInput()
        var router = ActionRouter(
            profile: ControllerProfile(name: "test", bindings: [.r1: .tapSequence([controlB])])
        )

        #expect(router.handle(input.press(.r1)) == [.tap(controlB)])
    }

    // MARK: - Storage

    @Test("a tap sequence round-trips through profile JSON")
    func roundTripsThroughJSON() throws {
        let profile = ControllerProfile(
            name: "test",
            bindings: [
                .r1: .tapSequence([controlB, KeyStroke(key: .n)]),
                .l3: .tapSequence([controlB, KeyStroke(key: .s)]),
                .cross: .tap(KeyStroke(key: .return)),
            ]
        )

        let decoded = try ControllerProfile(decodingJSON: try profile.encodedJSON())

        #expect(decoded.bindings == profile.bindings)
    }

    @Test("a stored sequence is written as comma-separated shortcuts a person can edit")
    func storedFormatIsReadable() throws {
        let profile = ControllerProfile(
            name: "test",
            bindings: [.r1: .tapSequence([controlB, KeyStroke(key: .n)])]
        )

        let text = String(decoding: try profile.encodedJSON(), as: UTF8.self)

        #expect(text.contains(#""kind" : "tapSequence""#))
        #expect(text.contains(#""keys" : "control+b, n""#))
    }

    @Test("a hand-written sequence is accepted with untidy spacing")
    func toleratesUntidySpacing() throws {
        let json = """
            {
              "schemaVersion": 2,
              "name": "hand written",
              "bindings": {
                "r1": { "kind": "tapSequence", "keys": "ctrl+b ,   n" }
              }
            }
            """

        let profile = try ControllerProfile(decodingJSON: Data(json.utf8))

        #expect(profile.binding(for: .r1) == .tapSequence([controlB, KeyStroke(key: .n)]))
    }

    @Test("an empty sequence is refused rather than silently doing nothing")
    func emptySequenceIsRefused() {
        let json = """
            {
              "schemaVersion": 2,
              "name": "broken",
              "bindings": { "r1": { "kind": "tapSequence", "keys": "  " } }
            }
            """

        #expect(throws: ProfileValidationError.emptyTapSequence(control: "r1")) {
            try ControllerProfile(decodingJSON: Data(json.utf8))
        }
    }

    @Test("an empty step is refused rather than silently removed")
    func emptyStepIsRefused() {
        let json = """
            {
              "schemaVersion": 2,
              "name": "broken",
              "bindings": { "r1": { "kind": "tapSequence", "keys": "control+b,,n" } }
            }
            """

        #expect(
            throws: ProfileValidationError.invalidShortcut(
                control: "r1",
                text: "",
                reason: "A tap sequence cannot contain an empty shortcut."
            )
        ) {
            try ControllerProfile(decodingJSON: Data(json.utf8))
        }
    }

    @Test("a sequence containing an unparseable shortcut names the offending text")
    func badStrokeInSequenceIsReported() {
        let json = """
            {
              "schemaVersion": 2,
              "name": "broken",
              "bindings": { "r1": { "kind": "tapSequence", "keys": "control+b, nope" } }
            }
            """

        var reported = ""
        #expect(throws: (any Error).self) {
            do {
                _ = try ControllerProfile(decodingJSON: Data(json.utf8))
            } catch let error as ProfileValidationError {
                reported = error.description
                throw error
            }
        }
        #expect(reported.contains("r1"))
        #expect(reported.contains("nope"))
    }

    @Test("a sequence of only modifiers is refused")
    func modifierOnlyStrokeIsRefused() {
        let json = """
            {
              "schemaVersion": 2,
              "name": "broken",
              "bindings": { "r1": { "kind": "tapSequence", "keys": "control+b, control" } }
            }
            """

        #expect(throws: (any Error).self) {
            try ControllerProfile(decodingJSON: Data(json.utf8))
        }
    }

    // MARK: - Diagnostics

    @Test("the CLI summary shows a sequence as an ordered list")
    func summaryShowsTheOrder() {
        let profile = ControllerProfile(
            name: "test",
            bindings: [.r1: .tapSequence([controlB, KeyStroke(key: .n)])]
        )

        #expect(profile.summaryLines == ["r1 -> tapSequence control+b, n"])
    }
}
