import SwiftUI
import CelestialCore

/// A searchable catalog of notable things in the galaxy: the brightest named stars,
/// known planetary systems, and curated deep-sky landmarks. Categories are
/// collapsible dropdowns for quick navigation; searching expands everything and
/// filters in place. Tapping an entry opens a detail page that can launch the
/// Galaxy Map focused on that object.
struct CatalogView: View {
    let store: StarCatalogStore
    let exo: ExoplanetStore
    @State private var query = ""
    @State private var allStars: [Star] = []           // every catalog star, brightest first
    @State private var namedStars: [Star] = []          // the curated "greatest hits"
    @State private var constellationGroups: [ConstellationGroup] = []
    /// Which dropdowns are open. Search overrides this to expand all (see `binding`).
    @State private var expandedKeys: Set<String> = ["notable"]

    /// All catalog stars in one constellation, brightest first.
    struct ConstellationGroup: Identifiable {
        let id: String          // constellation code ("CMa"), or "—" when unlisted
        let name: String        // full name ("Canis Major") or "Unlisted"
        let stars: [Star]
    }

    var body: some View {
        List {
            if isSearching {
                let matches = matchingStars
                disclosure("stars", title: "Stars", systemImage: "sparkle", tint: .yellow,
                           count: matches.count) {
                    ForEach(matches, id: \.id) { star in starLink(star) }
                }
            } else {
                disclosure("notable", title: "Notable Stars", systemImage: "star.fill", tint: .yellow,
                           count: namedStars.count) {
                    ForEach(namedStars, id: \.id) { star in starLink(star) }
                }
                disclosure("constellations", title: "Stars by Constellation", systemImage: "sparkles",
                           tint: .yellow, count: allStars.count) {
                    ForEach(constellationGroups) { group in
                        disclosure("con.\(group.id)", title: group.name, systemImage: "star",
                                   tint: .yellow.opacity(0.85), count: group.stars.count) {
                            ForEach(group.stars, id: \.id) { star in starLink(star) }
                        }
                    }
                }
            }

            disclosure("systems", title: "Planetary Systems", systemImage: "circle.dotted.circle", tint: .cyan,
                       count: filteredSystems.count) {
                ForEach(filteredSystems) { system in
                    NavigationLink { SystemView(system: system) } label: { systemRow(system) }
                }
            }

            disclosure("deepsky", title: "Deep Sky", systemImage: "circle.hexagongrid.fill", tint: .purple,
                       count: filteredDeepSky.count) {
                ForEach(deepSkyKinds, id: \.self) { kind in
                    let items = filteredDeepSky.filter { $0.kind == kind }
                    disclosure("ds.\(kind)", title: kind.label, systemImage: "sparkle",
                               tint: .purple.opacity(0.85), count: items.count) {
                        ForEach(items) { object in
                            NavigationLink { DeepSkyDetailView(object: object) } label: { deepSkyRow(object) }
                        }
                    }
                }
            }

            ForEach(LandmarkGroup.allCases, id: \.self) { group in
                let items = filteredLandmarks(in: group)
                disclosure(group.rawValue, title: group.title, systemImage: group.symbol,
                           tint: group.color, count: items.count) {
                    ForEach(items) { landmark in
                        NavigationLink { LandmarkDetailView(landmark: landmark, store: store, exo: exo) } label: {
                            landmarkRow(landmark)
                        }
                    }
                }
            }
        }
        .navigationTitle("Catalog")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { searchBar }
        .task(id: store.catalog?.count ?? 0) {
            guard allStars.isEmpty, let catalog = store.catalog else { return }
            let sorted = catalog.stars.sorted { $0.apparentMagnitude < $1.apparentMagnitude }
            allStars = sorted
            namedStars = sorted.filter { $0.properName != nil }

            // Bucket every star by its constellation so the whole catalog is
            // browsable, not just the named handful. Sorted by full name.
            var buckets: [String: [Star]] = [:]
            for star in sorted { buckets[star.constellation ?? "", default: []].append(star) }
            constellationGroups = buckets.map { code, stars in
                ConstellationGroup(id: code.isEmpty ? "—" : code,
                                   name: StarFacts.constellationName(code) ?? (code.isEmpty ? "Unlisted" : code),
                                   stars: stars)
            }
            .sorted { $0.name < $1.name }
        }
    }

    // MARK: Search

    /// A custom search field pinned to the bottom of the screen (so it sits in
    /// thumb reach), in the app's luminous language and without the system search's
    /// magnifying-glass affordance.
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle")
                .font(.footnote)
                .foregroundStyle(Theme.accent.opacity(0.8))
            TextField("Search stars, planets, nebulae…", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    // MARK: Dropdown

    /// A collapsible category section. Hidden entirely when it has no matches so a
    /// search doesn't leave a row of empty headers. Forced open while searching.
    @ViewBuilder
    private func disclosure<Content: View>(_ key: String, title: String, systemImage: String,
                                           tint: Color, count: Int,
                                           @ViewBuilder content: @escaping () -> Content) -> some View {
        if count > 0 {
            DisclosureGroup(isExpanded: binding(key)) {
                content()
            } label: {
                Label {
                    HStack {
                        Text(title).font(.headline)
                        Spacer()
                        Text("\(count)").font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .foregroundStyle(tint)
                        .frame(width: 30)
                }
            }
        }
    }

    private func binding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { !query.trimmingCharacters(in: .whitespaces).isEmpty || expandedKeys.contains(key) },
            set: { isOpen in
                if isOpen { expandedKeys.insert(key) } else { expandedKeys.remove(key) }
            })
    }

    // MARK: Filtering

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces).lowercased() }
    private var isSearching: Bool { !trimmedQuery.isEmpty }

    /// All stars matching the query, brightest first, capped so a broad query (e.g.
    /// a single constellation) stays snappy to render.
    private var matchingStars: [Star] {
        let q = trimmedQuery
        return Array(allStars.lazy.filter { StarFacts.matches($0, query: q) }.prefix(400))
    }

    private func filteredLandmarks(in group: LandmarkGroup) -> [Landmark] {
        let q = trimmedQuery
        return Landmarks.all.filter { landmark in
            landmark.type.group == group && (q.isEmpty
                || landmark.name.lowercased().contains(q)
                || (landmark.designation ?? "").lowercased().contains(q)
                || landmark.type.label.lowercased().contains(q))
        }
    }

    private var filteredSystems: [PlanetarySystem] {
        let q = trimmedQuery
        guard !q.isEmpty else {
            return Array(exo.systems.sorted { $0.planets.count > $1.planets.count }.prefix(60))
        }
        return exo.systems.filter {
            $0.hostName.lowercased().contains(q)
            || $0.planets.contains { $0.name.lowercased().contains(q) }
        }
    }

    // MARK: Rows

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

    private func starLink(_ star: Star) -> some View {
        NavigationLink { StarDetailView(star: star, store: store, exo: exo) } label: { starRow(star) }
    }

    // MARK: Deep sky

    /// Kinds present in the catalog, in a friendly browsing order.
    private var deepSkyKinds: [DeepSkyObject.Kind] {
        DeepSkyObject.Kind.allCases.filter { kind in filteredDeepSky.contains { $0.kind == kind } }
    }

    /// All deep-sky objects (brightest first), filtered by the search query.
    private var filteredDeepSky: [DeepSkyObject] {
        let all = DeepSky.all.sorted { ($0.magnitude ?? 99) < ($1.magnitude ?? 99) }
        guard isSearching else { return all }
        let q = trimmedQuery
        return all.filter {
            $0.id.lowercased().contains(q)
                || ($0.name?.lowercased().contains(q) ?? false)
                || ($0.constellation?.lowercased().contains(q) ?? false)
                || (StarFacts.constellationName($0.constellation)?.lowercased().contains(q) ?? false)
                || $0.kind.label.lowercased().contains(q)
        }
    }

    private func deepSkyRow(_ object: DeepSkyObject) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(object.name ?? object.id)
                Text([object.id, StarFacts.constellationName(object.constellation) ?? object.constellation,
                      object.magnitude.map { String(format: "mag %.1f", $0) }]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "sparkles").foregroundStyle(.purple)
        }
    }

    private func starRow(_ star: Star) -> some View {
        let title = StarFacts.displayName(for: star)
        let subtitle = [
            star.bayerFlamsteed == title ? nil : star.bayerFlamsteed,
            StarFacts.constellationName(star.constellation) ?? star.constellation,
            String(format: "mag %.1f", star.apparentMagnitude),
        ].compactMap { $0 }.joined(separator: " · ")
        return Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: star.properName != nil ? "sparkle" : "star")
                .foregroundStyle(.yellow)
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

    @State private var hrPopulation: [HRPoint] = []

    private var temperature: Double? { StarFacts.temperatureKelvin(colorIndex: star.colorIndex) }
    private var summary: String? { StarFacts.summary(for: star.properName) }
    private var spectral: String? { StarFacts.spectralDescription(star.spectralType) }
    private var radiusSolar: Double? { StarFacts.radiusSolar(for: star) }
    private var facts: [String] { StarFacts.relatableFacts(for: star) }
    private var lifeStory: String? { StarFacts.lifeStory(for: star) }
    private var hrHighlight: HRPoint? {
        guard let t = temperature, let l = star.luminosity else { return nil }
        return HRPoint(temperatureK: t, luminositySolar: l)
    }

    var body: some View {
        DetailScaffold(symbol: "sparkle", tint: .yellow, title: StarFacts.displayName(for: star),
                       subtitle: [star.bayerFlamsteed == StarFacts.displayName(for: star) ? nil : star.bayerFlamsteed,
                                  StarFacts.constellationName(star.constellation)]
                        .compactMap { $0 }.joined(separator: " · ")) {
            if let pc = star.distanceParsecs {
                DetailRow("Distance", String(format: "%.1f ly · %.1f pc", pc * 3.2616, pc))
            }
            DetailRow("Apparent magnitude", String(format: "%.2f", star.apparentMagnitude))
            if let abs = star.absoluteMagnitude { DetailRow("Absolute magnitude", String(format: "%.2f", abs)) }
            if let spect = star.spectralType { DetailRow("Spectral type", spect) }
            if let t = temperature { DetailRow("Surface temperature", String(format: "≈ %.0f K", t)) }
            if let l = star.luminosity { DetailRow("Luminosity", String(format: "%@ L☉", luminosityString(l))) }
            if let r = radiusSolar { DetailRow("Radius (derived)", String(format: "≈ %@ R☉", luminosityString(r))) }
            if let bv = star.colorIndex { DetailRow("Colour index (B−V)", String(format: "%.2f", bv)) }
            if let con = StarFacts.constellationName(star.constellation) { DetailRow("Constellation", con) }
            if let hip = star.hipparcos { DetailRow("Hipparcos", "HIP \(hip)") }
            if let hd = star.henryDraper { DetailRow("Henry Draper", "HD \(hd)") }
            if let hr = star.harvardRevised { DetailRow("Bright Star", "HR \(hr)") }
            if let gl = star.gliese { DetailRow("Gliese", gl) }
        } description: {
            VStack(alignment: .leading, spacing: 16) {
                if let summary { Text(summary) }
                if let spectral {
                    Label(spectral, systemImage: "thermometer.medium")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
                if let lifeStory {
                    Label(lifeStory, systemImage: "hourglass")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !facts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(facts, id: \.self) { fact in
                            Label(fact, systemImage: "sparkle")
                                .font(.subheadline).foregroundStyle(.white.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let hrHighlight, !hrPopulation.isEmpty {
                    HRDiagramView(population: hrPopulation, highlight: hrHighlight)
                }
                if let r = radiusSolar {
                    StarSizeView(starName: StarFacts.displayName(for: star),
                                 radiusSolar: r, temperatureK: temperature)
                }
            }
        } action: {
            if star.distanceParsecs != nil { GalaxyMapView(store: store, exo: exo, focus: .star(star.id)) }
        }
        .task(id: store.catalog?.count ?? 0) { buildHRPopulation() }
    }

    /// Samples the catalog into a background cloud for the HR diagram — every star
    /// with both a luminosity and a colour-derived temperature, thinned to keep the
    /// plot light to render.
    private func buildHRPopulation() {
        guard hrPopulation.isEmpty, let catalog = store.catalog else { return }
        var points: [HRPoint] = []
        points.reserveCapacity(1200)
        for s in catalog.stars {
            guard let l = s.luminosity, l > 0,
                  let t = StarFacts.temperatureKelvin(colorIndex: s.colorIndex), t > 0 else { continue }
            points.append(HRPoint(temperatureK: t, luminositySolar: l))
        }
        // Thin to ~900 evenly so the main sequence still reads but rendering stays cheap.
        let cap = 900
        if points.count > cap {
            let stride = Double(points.count) / Double(cap)
            hrPopulation = (0..<cap).map { points[Int(Double($0) * stride)] }
        } else {
            hrPopulation = points
        }
    }

    private func luminosityString(_ l: Double) -> String {
        l >= 100 ? String(format: "%.0f", l) : String(format: "%.2f", l)
    }
}

private struct DeepSkyDetailView: View {
    let object: DeepSkyObject

    var body: some View {
        DetailScaffold(symbol: symbol, tint: .purple, title: object.name ?? object.id,
                       subtitle: [object.id, object.kind.label,
                                  StarFacts.constellationName(object.constellation)]
                        .compactMap { $0 }.joined(separator: " · ")) {
            if let m = object.magnitude { DetailRow("Apparent magnitude", String(format: "%.1f", m)) }
            DetailRow("Type", object.kind.label)
            if let con = StarFacts.constellationName(object.constellation) { DetailRow("Constellation", con) }
            if let ly = object.distanceLightYears { DetailRow("Distance", distance(ly)) }
            if let size = object.angularSizeArcmin {
                DetailRow("Apparent size", size >= 60 ? String(format: "%.1f°", size / 60) : String(format: "%.0f′", size))
            }
            DetailRow("Right ascension", String(format: "%.2f°", object.equatorial.rightAscension.degrees))
            DetailRow("Declination", String(format: "%.2f°", object.equatorial.declination.degrees))
        } description: {
            Text(object.summary)
        } action: {
            EmptyView()
        }
    }

    private func distance(_ ly: Double) -> String {
        ly >= 1_000_000 ? String(format: "%.1f million ly", ly / 1_000_000)
                        : ly >= 10_000 ? String(format: "%.0fk ly", ly / 1_000)
                                       : String(format: "%.0f ly", ly)
    }

    private var symbol: String {
        switch object.kind {
        case .galaxy: "hurricane"
        case .globularCluster, .openCluster, .nebulaCluster: "circle.hexagongrid.fill"
        case .planetaryNebula, .emissionNebula, .reflectionNebula: "smoke.fill"
        case .supernovaRemnant: "rays"
        case .other: "sparkle"
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

                    // The Galaxy-Map link is omitted when the caller passes no action
                    // (an EmptyView) — e.g. deep-sky objects that aren't placed there.
                    if Action.self != EmptyView.self {
                        NavigationLink { action } label: {
                            Label("View in Galaxy Map", systemImage: "hurricane")
                                .font(.headline).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(LuminousButtonStyle(tint: .purple))
                    }
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
            GlossaryButton(label: label)
            Spacer()
            Text(value).foregroundStyle(.white).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.horizontal, 14).padding(.vertical, 11)
        .overlay(Divider().background(.white.opacity(0.08)), alignment: .bottom)
    }
}
