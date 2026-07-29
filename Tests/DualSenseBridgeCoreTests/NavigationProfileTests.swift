import Foundation
import Testing

@testable import DualSenseBridgeCore

@Suite("navigation settings persist in the profile without breaking old files")
struct NavigationProfileTests {
    /// A profile written by the S1 build: schema version 1 and no navigation
    /// section at all.
    private let legacyProfileJSON = """
        {
          "schemaVersion": 1,
          "name": "starter-terminal",
          "bindings": {
            "l2": { "kind": "hold", "keys": "control+option+space" },
            "cross": { "kind": "tap", "keys": "return" },
            "circle": { "kind": "tap", "keys": "escape" },
            "r3": { "kind": "tap", "keys": "control+c" }
          }
        }
        """

    @Test("an S1 profile still decodes and gets the default navigation settings")
    func legacyProfileDecodes() throws {
        let profile = try ControllerProfile(decodingJSON: Data(legacyProfileJSON.utf8))

        #expect(profile.name == "starter-terminal")
        #expect(profile.binding(for: .l2) == .hold(try KeyStroke(parsing: "control+option+space")))
        #expect(profile.navigation == .default)
        // The in-memory model is always the current schema, so a loaded v1 file
        // is upgraded rather than re-saved in a shape this build cannot read.
        #expect(profile.schemaVersion == ControllerProfile.currentSchemaVersion)
    }

    @Test("the current schema version is newer than the S1 one and both are accepted")
    func supportedVersions() {
        #expect(ControllerProfile.currentSchemaVersion == 2)
        #expect(ControllerProfile.supportedSchemaVersions.contains(1))
        #expect(ControllerProfile.supportedSchemaVersions.contains(2))
        #expect(!ControllerProfile.supportedSchemaVersions.contains(3))
    }

    @Test("an unsupported schema version is still refused and named")
    func unsupportedVersionIsRefused() {
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

    @Test("navigation settings round-trip through JSON")
    func navigationRoundTrips() throws {
        var navigation = NavigationSettings.default
        navigation.pointer.speed = 512
        navigation.pointer.deadzone = 0.11
        navigation.pointer.responseExponent = 1.5
        navigation.scroll.invertY = true
        navigation.tickInterval = 0.02
        let profile = ControllerProfile(
            name: "tuned",
            bindings: ControllerProfile.starterTerminal.bindings,
            navigation: navigation
        )

        let encoded = try profile.encodedJSON()
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(text.contains(#""navigation""#))
        #expect(text.contains(#""pointer""#))
        #expect(text.contains(#""deadzone""#))
        #expect(try ControllerProfile(decodingJSON: encoded) == profile)
    }

    @Test("a partial navigation section keeps the defaults for what it omits")
    func partialNavigationSectionUsesDefaults() throws {
        let json = """
            {
              "schemaVersion": 2,
              "name": "partial",
              "bindings": {},
              "navigation": { "pointer": { "speed": 250 } }
            }
            """
        let profile = try ControllerProfile(decodingJSON: Data(json.utf8))

        #expect(profile.navigation.pointer.speed == 250)
        #expect(profile.navigation.pointer.deadzone == NavigationSettings.default.pointer.deadzone)
        #expect(profile.navigation.scroll == NavigationSettings.default.scroll)
        #expect(profile.navigation.tickInterval == NavigationSettings.default.tickInterval)
    }

    @Test("an out-of-range navigation value is refused instead of steering the cursor")
    func invalidNavigationIsRefused() {
        let json = """
            {
              "schemaVersion": 2,
              "name": "reckless",
              "bindings": {},
              "navigation": { "pointer": { "speed": 500000 } }
            }
            """

        #expect(throws: ProfileValidationError.self) {
            try ControllerProfile(decodingJSON: Data(json.utf8))
        }
    }

    @Test("a refused navigation value names the field and the accepted range")
    func invalidNavigationIsExplained() throws {
        let json = """
            {
              "schemaVersion": 2,
              "name": "reckless",
              "bindings": {},
              "navigation": { "scroll": { "deadzone": 0.99 } }
            }
            """

        var reported = ""
        do {
            _ = try ControllerProfile(decodingJSON: Data(json.utf8))
        } catch let error as ProfileValidationError {
            reported = error.description
        }

        #expect(reported.contains("scroll.deadzone"))
        #expect(reported.contains("0.9"))
    }

    @Test("the starter profile carries the default navigation settings")
    func starterProfileNavigation() {
        #expect(ControllerProfile.starterTerminal.navigation == .default)
    }

    @Test("a profile summary shows the active navigation values for diagnostics")
    func summaryIncludesNavigation() {
        let summary = ControllerProfile.starterTerminal.navigationSummaryLines.joined(separator: "\n")

        #expect(summary.contains("right stick -> pointer"))
        #expect(summary.contains("left stick -> scroll"))
    }

    @Test("a loader reports an invalid navigation section with the file path")
    func loaderReportsNavigationProblems() {
        let loader = ProfileLoader { _ in
            Data(
                """
                {"schemaVersion": 2, "name": "x", "bindings": {}, "navigation": {"pointer": {"deadzone": -1}}}
                """.utf8
            )
        }

        #expect(throws: ProfileLoadError.self) { try loader.load(path: "/tmp/does-not-matter.json") }
    }
}
