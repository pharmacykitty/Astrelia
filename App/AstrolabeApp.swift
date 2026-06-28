import SwiftUI
import SwiftData
import CelestialCore

@main
struct AstrolabeApp: App {
    var body: some Scene {
        WindowGroup {
            // Debug-only snapshot route so the 3D sphere can be captured directly
            // (the menu can't be scripted in the simulator). Pass `-snapshotSphere`.
            if ProcessInfo.processInfo.arguments.contains("-snapshotSphere") {
                NavigationStack { SphereSnapshotHarness() }
                    .preferredColorScheme(.dark)
            } else if ProcessInfo.processInfo.arguments.contains("-snapshotStar") {
                NavigationStack { StarSnapshotHarness() }
                    .preferredColorScheme(.dark)
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
