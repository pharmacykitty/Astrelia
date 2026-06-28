import SwiftUI
import SwiftData

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
            } else {
                ContentView()
            }
        }
        .modelContainer(for: SavedChart.self)
    }
}
