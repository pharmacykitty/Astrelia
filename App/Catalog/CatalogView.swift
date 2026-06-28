import SwiftUI
import CelestialCore

/// A searchable catalog of notable things in the galaxy: curated deep-sky
/// landmarks and the brightest named stars. Tapping an entry opens a detail page
/// that can launch the Galaxy Map focused on that object.
struct CatalogView: View {
    let store: StarCatalogStore
    let exo: ExoplanetStore
    @State private var query = ""
    @State private var namedStars: [Star] = []

    var body: some View {
        List {
            if !filteredLandmarks.isEmpty {
                Section("Landmarks") {
                    ForEach(filteredLandmarks) { landmark in
                        NavigationLink {
                            LandmarkDetailView(landmark: landmark, store: store, exo: exo)
                        } label: {
                            landmarkRow(landmark)
                        }
                    }
                }
            }
            if !filteredSystems.isEmpty {
                Section(query.isEmpty ? "Planetary Systems" : "Systems") {
                    ForEach(filteredSystems) { system in
                        NavigationLink {
                            SystemView(system: system)
                        } label: {
                            systemRow(system)
                        }
                    }
                }
            }
            if !filteredStars.isEmpty {
                Section(query.isEmpty ? "Brightest Stars" : "Stars") {
                    ForEach(filteredStars, id: \.id) { star in
                        NavigationLink {
                            StarDetailView(star: star, store: store, exo: exo)
                        } label: {
                            starRow(star)
                        }
                    }
                }
            }
        }
        .navigationTitle("Catalog")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search stars, planets, nebulae…")
        .task(id: store.catalog?.count ?? 0) {
            guard namedStars.isEmpty, let catalog = store.catalog else { return }
            namedStars = catalog.stars
                .filter { $0.properName != nil }
                .sorted { $0.apparentMagnitude < $1.apparentMagnitude }
        }
    }

    private var filteredLandmarks: [Landmark] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Landmarks.all }
        return Landmarks.all.filter {
            $0.name.lowercased().contains(q)
            || ($0.designation ?? "").lowercased().contains(q)
            || $0.type.label.lowercased().contains(q)
        }
    }

    private var filteredStars: [Star] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Array(namedStars.prefix(150)) }
        return namedStars.filter {
            ($0.properName ?? "").lowercased().contains(q)
            || ($0.bayerFlamsteed ?? "").lowercased().contains(q)
            || ($0.constellation ?? "").lowercased().contains(q)
        }
    }

    private var filteredSystems: [PlanetarySystem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else {
            return Array(exo.systems.sorted { $0.planets.count > $1.planets.count }.prefix(60))
        }
        return exo.systems.filter {
            $0.hostName.lowercased().contains(q)
            || $0.planets.contains { $0.name.lowercased().contains(q) }
        }
    }

    private func systemRow(_ system: PlanetarySystem) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(system.hostName)
                Text([
                    "\(system.planets.count) planet\(system.planets.count == 1 ? "" : "s")",
                    system.spectralType,
                    system.distanceLightYears.map { String(format: "%.0f ly", $0) },
                ].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "circle.dotted.circle").foregroundStyle(.cyan)
        }
    }

    private func landmarkRow(_ landmark: Landmark) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(landmark.name)
                Text([landmark.designation, landmark.type.label].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: landmark.type.symbol).foregroundStyle(landmark.type.color)
        }
    }

    private func starRow(_ star: Star) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(star.properName ?? "Star \(star.id)")
                Text([star.bayerFlamsteed, star.constellation, String(format: "mag %.1f", star.apparentMagnitude)]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "sparkle").foregroundStyle(.yellow)
        }
    }
}

// MARK: - Detail pages

private struct LandmarkDetailView: View {
    let landmark: Landmark
    let store: StarCatalogStore
    let exo: ExoplanetStore

    var body: some View {
        DetailScaffold(symbol: landmark.type.symbol, tint: landmark.type.color, title: landmark.name,
                       subtitle: [landmark.designation, landmark.type.label].compactMap { $0 }.joined(separator: " · ")) {
            DetailRow("Distance", String(format: "%@ ly · %@ pc",
                                         number(landmark.distanceLightYears), number(landmark.distanceParsecs)))
            DetailRow("Right ascension", String(format: "%.2f°", landmark.raDegrees))
            DetailRow("Declination", String(format: "%.2f°", landmark.decDegrees))
            DetailRow("Type", landmark.type.label)
        } description: {
            Text(landmark.summary)
        } action: {
            GalaxyMapView(store: store, exo: exo, focus: .landmark(landmark))
        }
    }

    private func number(_ value: Double) -> String {
        value >= 10000 ? String(format: "%.0fk", value / 1000) : String(format: "%.0f", value)
    }
}

private struct StarDetailView: View {
    let star: Star
    let store: StarCatalogStore
    let exo: ExoplanetStore

    var body: some View {
        DetailScaffold(symbol: "sparkle", tint: .yellow, title: star.properName ?? "Star \(star.id)",
                       subtitle: [star.bayerFlamsteed, star.constellation].compactMap { $0 }.joined(separator: " · ")) {
            if let pc = star.distanceParsecs {
                DetailRow("Distance", String(format: "%.1f ly · %.1f pc", pc * 3.2616, pc))
            }
            DetailRow("Apparent magnitude", String(format: "%.2f", star.apparentMagnitude))
            if let abs = star.absoluteMagnitude { DetailRow("Absolute magnitude", String(format: "%.2f", abs)) }
            if let spect = star.spectralType { DetailRow("Spectral type", spect) }
            if let hip = star.hipparcos { DetailRow("Hipparcos", "HIP \(hip)") }
        } description: {
            EmptyView()
        } action: {
            if star.distanceParsecs != nil { GalaxyMapView(store: store, exo: exo, focus: .star(star.id)) }
        }
    }
}

/// Shared layout for a catalog detail page: header, fact rows, blurb, and a
/// "View in Galaxy Map" link (omitted when `action` builds an empty view).
private struct DetailScaffold<Facts: View, Description: View, Action: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    @ViewBuilder var facts: Facts
    @ViewBuilder var description: Description
    @ViewBuilder var action: Action

    var body: some View {
        ZStack {
            Theme.spaceGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 12) {
                        LuminousGlyph(symbol: symbol, tint: tint, size: 96, glyphSize: 42)
                        Text(title).font(.system(.largeTitle, design: .serif).weight(.bold))
                            .foregroundStyle(.white).multilineTextAlignment(.center)
                        if !subtitle.isEmpty {
                            Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                    VStack(spacing: 0) { facts }
                        .luminousSurface(tint)

                    description.font(.body).foregroundStyle(.white.opacity(0.8))

                    NavigationLink { action } label: {
                        Label("View in Galaxy Map", systemImage: "hurricane")
                            .font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LuminousButtonStyle(tint: .purple))
                }
                .padding()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value).foregroundStyle(.white).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.horizontal, 14).padding(.vertical, 11)
        .overlay(Divider().background(.white.opacity(0.08)), alignment: .bottom)
    }
}
