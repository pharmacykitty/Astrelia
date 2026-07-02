import SwiftUI
import SwiftData
import CelestialCore
import Astrology

/// Debug-only: renders an individual astrology screen for screenshotting from the
/// simulator (the menu can't be scripted). Reached via `-snapshotAstro <screen>`,
/// where screen ∈ home | detail | transits | editor | list | reading |
/// relationships | synastry.
struct AstrologySnapshotHarness: View {
    let screen: String
    @State private var store = StarCatalogStore()

    private var sample: NatalChart { SphereSnapshotHarness.sampleChart }

    var body: some View {
        Group {
            switch screen {
            case "home":
                NavigationStack { AstrologyHomeView(store: store) }
            case "transits":
                NavigationStack { TransitsView(natal: sample, title: "Sample") }
            case "editor":
                ChartEditorView()
            case "list":
                NavigationStack { ChartListView(store: store) }
            case "relationships":
                NavigationStack { RelationshipsView(store: store) }
                    .modelContainer(Self.sampleContainer)
            case "synastry":
                SynastrySnapshot().modelContainer(Self.sampleContainer)
            case "guide":
                SphereGuideSheet(chart: sample)
            case "progressions":
                NavigationStack { PredictiveView(natal: sample, title: "Sample", initialMode: .progressions) }
            case "solarreturn":
                NavigationStack { PredictiveView(natal: sample, title: "Sample", initialMode: .solar) }
            case "reading":
                ReadingSheet(reading: Reading(
                    title: "Sun in Scorpio",
                    sections: Interpretation.planetReading(.sun, sign: .scorpio, house: 10,
                        dignity: .none, aspects: [(.square, .uranus), (.trine, .moon)])),
                    tint: AppScreen.astrology.tint)
            default: // "detail"
                NavigationStack {
                    ChartDetailView(chart: sample, title: "Sample",
                                    subtitle: "19 Nov 1971 · Seattle", natalForTransits: sample)
                }
            }
        }
        .task { store.loadIfNeeded() }
    }

    /// An in-memory container with two sample charts for the relationship screens.
    @MainActor static let sampleContainer: ModelContainer = {
        let c = try! ModelContainer(for: SavedChart.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let a = SavedChart(name: "Ada", year: 1815, month: 12, day: 10, hour: 7, minute: 0,
            timeKnown: true, latitude: 51.5074, longitude: -0.1278,
            timeZoneIdentifier: "Europe/London", placeName: "London")
        let b = SavedChart(name: "Alan", year: 1912, month: 6, day: 23, hour: 2, minute: 15,
            timeKnown: true, latitude: 51.5074, longitude: -0.1278,
            timeZoneIdentifier: "Europe/London", placeName: "London")
        c.mainContext.insert(a)
        c.mainContext.insert(b)
        try? c.mainContext.save()   // stable persistentModelIDs for the pickers
        return c
    }()
}

/// Wrapper that reads the two sample charts from the in-memory container.
private struct SynastrySnapshot: View {
    @Query(sort: \SavedChart.createdAt) private var charts: [SavedChart]
    var body: some View {
        NavigationStack {
            if charts.count >= 2 {
                SynastryView(personA: charts[0], personB: charts[1])
            } else {
                Text("No sample charts").foregroundStyle(.white)
            }
        }
    }
}
