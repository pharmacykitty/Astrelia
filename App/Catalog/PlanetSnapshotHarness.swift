import SwiftUI

/// Debug-only: renders `PlanetDetailView` for a sample Solar System world so the
/// planet detail sheet can be screenshotted from the simulator. Reached via the
/// `-snapshotPlanet` launch arg (see `AstrolabeApp`). Defaults to Earth; pass a
/// planet name as the next argument to pick another (e.g. "Jupiter").
struct PlanetSnapshotHarness: View {
    var planetName: String = "Earth"

    var body: some View {
        let system = SolarSystem.system
        let planet = system.planets.first { $0.name == planetName } ?? system.planets[2]
        PlanetDetailView(planet: planet, system: system)
    }
}
