import SwiftUI
import CelestialCore
import Astrology

/// Debug-only: renders `CelestialSphereView` for a fixed sample chart so it can be
/// screenshotted from the simulator (reached via the `-snapshotSphere` launch arg).
/// Sample = the reference GIF's data: 19 Nov 1971, 11:01 PST, Seattle.
struct SphereSnapshotHarness: View {
    @State private var store = StarCatalogStore()
    var body: some View {
        CelestialSphereView(chart: Self.sampleChart, title: "Sample",
                            subtitle: "19 Nov 1971 · Seattle",
                            stars: SphereStars.bright(from: store),
                            constellations: store.constellations)
            .task { store.loadIfNeeded() }
    }

    static var sampleChart: NatalChart {
        var comps = DateComponents()
        comps.year = 1971; comps.month = 11; comps.day = 19
        comps.hour = 11; comps.minute = 1
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        let date = cal.date(from: comps) ?? Date()
        let loc = GeographicLocation(latitude: .degrees(47.6062), longitude: .degrees(-122.3321))
        return NatalChart(at: JulianDay(date), location: loc,
                          settings: ChartSettings(houseSystem: .placidus, zodiac: .tropical))
    }
}
