import Foundation
import Testing

@testable import DualSenseBridgeCore

@Suite("navigation settings are validated before they can steer the cursor")
struct NavigationSettingsTests {
    @Test("the defaults are conservative and valid")
    func defaultsAreValid() throws {
        let settings = NavigationSettings.default

        try settings.validate()
        #expect(settings.pointer.deadzone > 0)
        #expect(settings.scroll.deadzone > 0)
        #expect(settings.pointer.speed == 1_560)
        #expect(settings.scroll.speed <= 1_560)
        #expect(settings.tickInterval <= 0.02)
        #expect(settings.maximumTickInterval >= settings.tickInterval)
    }

    @Test("a deadzone that swallows the whole stick is refused")
    func deadzoneIsRangeChecked() {
        var settings = NavigationSettings.default
        settings.pointer.deadzone = 0.95

        #expect(throws: NavigationSettingsError.outOfRange(field: "pointer.deadzone", value: 0.95, expected: "0 up to 0.9")) {
            try settings.validate()
        }
    }

    @Test("a zero or negative speed is refused rather than silently ignored")
    func speedIsRangeChecked() {
        var settings = NavigationSettings.default
        settings.scroll.speed = 0

        #expect(throws: NavigationSettingsError.self) { try settings.validate() }
    }

    @Test("an absurd speed is refused so the cursor cannot be flung")
    func speedHasACeiling() {
        var settings = NavigationSettings.default
        settings.pointer.speed = 99_999

        #expect(throws: NavigationSettingsError.self) { try settings.validate() }
    }

    @Test("a non-finite setting is refused")
    func nonFiniteSettingsAreRefused() {
        var settings = NavigationSettings.default
        settings.pointer.speed = .nan

        #expect(throws: NavigationSettingsError.self) { try settings.validate() }
    }

    @Test("a tick interval outside the usable range is refused")
    func tickIntervalIsRangeChecked() {
        var settings = NavigationSettings.default
        settings.tickInterval = 5

        #expect(throws: NavigationSettingsError.self) { try settings.validate() }
    }

    @Test("the stall clamp may not be shorter than one tick")
    func stallClampMustCoverATick() {
        var settings = NavigationSettings.default
        settings.maximumTickInterval = settings.tickInterval / 2

        #expect(throws: NavigationSettingsError.self) { try settings.validate() }
    }

    @Test("validation errors read as guidance a user can act on")
    func errorsAreReadable() {
        #expect(
            NavigationSettingsError.outOfRange(field: "pointer.speed", value: 0, expected: "above 0 and at most 5000")
                .description
                == #"Navigation setting "pointer.speed" is 0; it must be above 0 and at most 5000."#
        )
    }

    @Test("an enormous value is explained rather than crashing the explanation")
    func hugeValuesAreDescribedSafely() throws {
        // Regression: an integral Double this large overflows Int, so spelling it
        // as an integer used to trap inside the error message itself.
        var settings = NavigationSettings.default
        settings.pointer.speed = 1e300

        #expect(throws: NavigationSettingsError.self) { try settings.validate() }

        let description = NavigationSettingsError
            .outOfRange(field: "pointer.speed", value: 1e300, expected: "above 0 and at most 5000")
            .description
        #expect(description.contains("pointer.speed"))
        #expect(description.contains("1e+300"))
    }

    @Test("a profile carrying an enormous value is refused with a readable reason")
    func hugeValueInAProfileIsRefused() throws {
        let json = """
            {
              "schemaVersion": 2,
              "name": "absurd",
              "bindings": {},
              "navigation": { "pointer": { "speed": 1e300 } }
            }
            """

        var reported = ""
        do {
            _ = try ControllerProfile(decodingJSON: Data(json.utf8))
        } catch let error as ProfileValidationError {
            reported = error.description
        }

        #expect(reported.contains("pointer.speed"))
    }

    @Test("a non-finite value is named rather than printed as a number")
    func nonFiniteValuesAreDescribed() {
        #expect(
            NavigationSettingsError
                .outOfRange(field: "pointer.speed", value: .nan, expected: "above 0 and at most 5000")
                .description
                .contains("not a finite number")
        )
    }

    @Test("a fractional value keeps its decimals in the message")
    func fractionalValuesAreDescribed() {
        #expect(
            NavigationSettingsError
                .outOfRange(field: "scroll.deadzone", value: 0.99, expected: "0 up to 0.9")
                .description
                == #"Navigation setting "scroll.deadzone" is 0.99; it must be 0 up to 0.9."#
        )
    }

    @Test("settings summarize themselves for diagnostics without machine details")
    func summaryLines() {
        let lines = NavigationSettings.default.summaryLines
        let joined = lines.joined(separator: "\n")

        #expect(lines.contains { $0.hasPrefix("right stick -> pointer") })
        #expect(lines.contains { $0.hasPrefix("left stick -> scroll") })
        #expect(joined.contains("deadzone"))
        #expect(joined.contains("curve"))
        #expect(joined.contains("px/s"))
        #expect(joined.contains("tick"))
        #expect(!joined.contains("/Users"))
    }
}
