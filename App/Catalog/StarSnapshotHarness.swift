import SwiftUI
import CelestialCore

/// Debug-only: renders the star-detail comparison widgets (HR diagram, size-vs-Sun
/// silhouette, relatable facts, life story) for a sample star, so they can be
/// screenshotted from the simulator where the catalog UI can't be scripted. Reached
/// via the `-snapshotStar` launch arg (see `AstrolabeApp`).
struct StarSnapshotHarness: View {
    @State private var store = StarCatalogStore()
    @State private var population: [HRPoint] = []

    var body: some View {
        ZStack {
            Theme.spaceGradient.ignoresSafeArea()
            ScrollView {
                if let star {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(StarFacts.displayName(for: star))
                            .font(.system(.largeTitle, design: .serif).weight(.bold))
                            .foregroundStyle(.white)
                        if let story = StarFacts.lifeStory(for: star) {
                            Label(story, systemImage: "hourglass")
                                .font(.subheadline).foregroundStyle(.white.opacity(0.75))
                        }
                        ForEach(StarFacts.relatableFacts(for: star), id: \.self) { fact in
                            Label(fact, systemImage: "sparkle")
                                .font(.subheadline).foregroundStyle(.white.opacity(0.75))
                        }
                        if let h = highlight, !population.isEmpty {
                            HRDiagramView(population: population, highlight: h)
                        }
                        if let r = StarFacts.radiusSolar(for: star) {
                            StarSizeView(starName: StarFacts.displayName(for: star), radiusSolar: r,
                                         temperatureK: StarFacts.temperatureKelvin(colorIndex: star.colorIndex))
                        }
                    }
                    .padding()
                } else {
                    ProgressView().tint(.white)
                }
            }
        }
        .task {
            store.loadIfNeeded()
            // Wait for the catalog, then build the background cloud.
            while store.catalog == nil { try? await Task.sleep(for: .milliseconds(50)) }
            buildPopulation()
        }
    }

    /// A vivid example: Betelgeuse if present (a red supergiant — dramatic on both
    /// widgets), else the brightest star with full data.
    private var star: Star? {
        guard let catalog = store.catalog else { return nil }
        return catalog.stars.first { $0.properName == "Betelgeuse" }
            ?? catalog.stars.filter { $0.luminosity != nil && $0.colorIndex != nil }
                .min { $0.apparentMagnitude < $1.apparentMagnitude }
    }

    private var highlight: HRPoint? {
        guard let star, let t = StarFacts.temperatureKelvin(colorIndex: star.colorIndex),
              let l = star.luminosity else { return nil }
        return HRPoint(temperatureK: t, luminositySolar: l)
    }

    private func buildPopulation() {
        guard let catalog = store.catalog else { return }
        var points: [HRPoint] = []
        for s in catalog.stars {
            guard let l = s.luminosity, l > 0,
                  let t = StarFacts.temperatureKelvin(colorIndex: s.colorIndex), t > 0 else { continue }
            points.append(HRPoint(temperatureK: t, luminositySolar: l))
        }
        let cap = 900
        if points.count > cap {
            let stride = Double(points.count) / Double(cap)
            population = (0..<cap).map { points[Int(Double($0) * stride)] }
        } else {
            population = points
        }
    }
}
