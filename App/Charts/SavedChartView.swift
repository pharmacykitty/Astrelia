import SwiftUI
import Astrology

/// A saved birth chart, recomputed from its stored inputs. Reuses the shared
/// `ChartDetailView`, with a link to the 3D sphere.
///
/// The chart is computed **once** in `.task` and cached, rather than rebuilt on
/// every render — building a chart is ~36 ephemeris evaluations, so doing it in
/// `body` made the page lag on every scroll/state change.
struct SavedChartView: View {
    let chart: SavedChart
    var store: StarCatalogStore? = nil

    @State private var natal: NatalChart?

    private var name: String { chart.name.isEmpty ? "Chart" : chart.name }

    var body: some View {
        Group {
            if let natal {
                ChartDetailView(
                    chart: natal,
                    title: name,
                    subtitle: chart.subtitle,
                    natalForTransits: natal,
                    toolbarTrailing: AnyView(sphereLink(natal))
                )
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.spaceGradient.ignoresSafeArea())
                    .navigationTitle(name)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task(id: chart.persistentModelID) { natal = chart.makeChart() }
    }

    private func sphereLink(_ natal: NatalChart) -> some View {
        NavigationLink {
            CelestialSphereView(chart: natal, title: name,
                                subtitle: chart.subtitle, stars: SphereStars.bright(from: store),
                                constellations: store?.constellations ?? [])
        } label: {
            Image(systemName: "globe").accessibilityLabel("View in 3D sphere")
        }
        .tint(AppScreen.astrology.tint)
    }
}
