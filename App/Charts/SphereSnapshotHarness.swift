import SwiftUI
import CelestialCore
import Astrology

/// Debug-only: renders `CelestialSphereView` for a fixed sample chart so it can be
/// screenshotted from the simulator (reached via the `-snapshotSphere` launch arg).
/// Sample = the reference GIF's data: 19 Nov 1971, 11:01 PST, Seattle.
struct SphereSnapshotHarness: View {
    @State private var store = StarCatalogStore()
    /// "tour" or "time" to auto-open those overlays for screenshots.
    var debugMode: String? = nil
    var body: some View {
        CelestialSphereView(chart: Self.sampleChart, title: "Sample",
                            subtitle: "19 Nov 1971 · Seattle",
                            stars: SphereStars.bright(from: store),
                            constellations: store.constellations,
                            debugMode: debugMode)
            .task { store.loadIfNeeded() }
    }

    /// Debug-only: runs the real GIF + MP4 export pipeline on the sample chart and
    /// writes the produced files and a status line into the app's Documents, so the
    /// encode path can be verified from the simulator without scripting taps.
    /// Reached via `-exportTest`.
    static func runExportTest() async {
        let chart = sampleChart
        var lines: [String] = []
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for format in [SphereExportFormat.gif, .mp4] {
            let result = await CelestialSphereView.debugExport(format, chart: chart)
            switch result {
            case .shareFile(let url):
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
                let dest = docs.appendingPathComponent("export-test.\(format.rawValue)")
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: url, to: dest)
                lines.append("\(format.rawValue): OK \(size) bytes -> \(dest.lastPathComponent)")
            case .failure(let message):
                lines.append("\(format.rawValue): FAIL \(message)")
            }
        }
        // Also render the three share-card styles.
        for style in ShareCardStyle.allCases {
            if let url = renderChartShareCard(chart: chart, title: "Sample", subtitle: "19 Nov 1971 · Seattle", style: style) {
                let dest = docs.appendingPathComponent("card-\(style.rawValue.prefix(4)).png")
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: url, to: dest)
                lines.append("card \(style.rawValue): OK")
            } else {
                lines.append("card \(style.rawValue): FAIL")
            }
        }

        try? lines.joined(separator: "\n").write(to: docs.appendingPathComponent("export-test.txt"),
                                                 atomically: true, encoding: .utf8)
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
