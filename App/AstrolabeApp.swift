import SwiftUI
import SwiftData
import CelestialCore

@main
struct AstrolabeApp: App {
    var body: some Scene {
        WindowGroup {
            // Debug-only snapshot route so the 3D sphere can be captured directly
            // (the menu can't be scripted in the simulator). Pass `-snapshotSphere`.
            if ProcessInfo.processInfo.arguments.contains("-exportTest") {
                Color.black.ignoresSafeArea()
                    .task { await SphereSnapshotHarness.runExportTest() }
            } else if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-snapshotSphere") {
                let args = ProcessInfo.processInfo.arguments
                let mode = (i + 1 < args.count && !args[i + 1].hasPrefix("-")) ? args[i + 1] : nil
                NavigationStack { SphereSnapshotHarness(debugMode: mode) }
                    .preferredColorScheme(.dark)
            } else if ProcessInfo.processInfo.arguments.contains("-snapshotStar") {
                NavigationStack { StarSnapshotHarness() }
                    .preferredColorScheme(.dark)
            } else if ProcessInfo.processInfo.arguments.contains("-galaxyBH") {
                // Debug: open the Galaxy Map at Sgr A* (add `-dive` to free-fly straight in).
                GalaxyBlackHoleHarness(dive: ProcessInfo.processInfo.arguments.contains("-dive"))
            } else if ProcessInfo.processInfo.arguments.contains("-snapshotTonight") {
                NavigationStack {
                    TonightView(fixedLocation: GeographicLocation(latitude: .degrees(40.71),
                                                                  longitude: .degrees(-74.0)))
                }
                .preferredColorScheme(.dark)
            } else if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-snapshotPlanet") {
                let args = ProcessInfo.processInfo.arguments
                let name = (i + 1 < args.count && !args[i + 1].hasPrefix("-")) ? args[i + 1] : "Earth"
                PlanetSnapshotHarness(planetName: name)
                    .preferredColorScheme(.dark)
            } else if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-snapshotAstro") {
                let args = ProcessInfo.processInfo.arguments
                let screen = (i + 1 < args.count) ? args[i + 1] : "detail"
                AstrologySnapshotHarness(screen: screen)
                    .preferredColorScheme(.dark)
            } else {
                ContentView()
            }
        }
        .modelContainer(for: SavedChart.self)
    }
}

/// Debug host for `-galaxyBH`: the Galaxy Map focused on Sagittarius A*, with its
/// own stores (the normal app path owns these in `ContentView`).
private struct GalaxyBlackHoleHarness: View {
    let dive: Bool
    @State private var store = StarCatalogStore()
    @State private var exo = ExoplanetStore()

    var body: some View {
        GalaxyMapView(store: store, exo: exo, focus: .blackHole(dive: dive))
            .task { store.loadIfNeeded(); exo.loadIfNeeded() }
            .preferredColorScheme(.dark)
    }
}
