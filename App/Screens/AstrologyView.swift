import SwiftUI
import CelestialCore
import Astrology

/// The live chart of the sky *right now* for the observer's location. A thin
/// wrapper over the shared `ChartDetailView`, plus a link to the 3D sphere.
struct SkyNowView: View {
    var store: StarCatalogStore? = nil
    @State private var model = AstrologyModel()

    var body: some View {
        ChartDetailView(
            chart: model.chart,
            title: "Sky Now",
            subtitle: model.locationLabel,
            toolbarTrailing: AnyView(
                NavigationLink {
                    CelestialSphereView(chart: model.chart, title: "Sky Now",
                                        stars: SphereStars.bright(from: store),
                                        constellations: store?.constellations ?? [])
                } label: {
                    Image(systemName: "globe")
                }
                .tint(AppScreen.astrology.tint)
            )
        )
        .task {
            store?.loadIfNeeded()
            await model.start()
        }
    }
}

/// Pulls a clean, bright subset of the catalog for the 3D sphere backdrop.
enum SphereStars {
    @MainActor
    static func bright(from store: StarCatalogStore?, magnitudeLimit: Double = 5.0) -> [Star] {
        guard let stars = store?.catalog?.stars else { return [] }
        return stars.filter { $0.apparentMagnitude <= magnitudeLimit }
    }
}

#Preview {
    NavigationStack { SkyNowView() }
        .preferredColorScheme(.dark)
}
