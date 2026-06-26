import Testing
@testable import CelestialCore

@Test("engine reports its version")
func engineHasVersion() {
    #expect(CelestialCore.version == "0.0.1")
}
