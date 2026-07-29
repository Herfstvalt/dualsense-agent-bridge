import Testing
@testable import DualSenseBridgeCore

@Test("the package exposes a semantic development version")
func versionIsPresent() {
    #expect(BridgeVersion.current == "0.1.0")
}

