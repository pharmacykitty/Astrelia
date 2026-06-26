import Testing
@testable import CelestialCore

@Test("engine reports its version")
func engineHasVersion() {
    #expect(CelestialCoreInfo.version == "0.0.1")
}
