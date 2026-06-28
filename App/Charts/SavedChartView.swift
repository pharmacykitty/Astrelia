import SwiftUI
import Astrology

/// A saved birth chart, recomputed from its stored inputs. Reuses the shared
/// `ChartDetailView`, with a link to the 3D sphere.
struct SavedChartView: View {
    let chart: SavedChart
    var store: StarCatalogStore? = nil

    var body: some View {
        let natal = chart.makeChart()
        ChartDetailView(
            chart: natal,
            title: chart.name.isEmpty ? "Chart" : chart.name,
            subtitle: chart.subtitle,
            toolbarTrailing: AnyView(
                NavigationLink {
                    CelestialSphereView(chart: natal, title: chart.name.isEmpty ? "Chart" : chart.name,
                                        subtitle: chart.subtitle, stars: SphereStars.bright(from: store),
                                        constellations: store?.constellations ?? [])
                } label: {
                    Image(systemName: "globe")
                }
                .tint(AppScreen.astrology.tint)
            )
        )
    }
}
