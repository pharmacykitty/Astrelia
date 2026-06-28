import SwiftUI
import simd
import CelestialCore

/// Browse and inspect the sky's figures across four collections — the official 88
/// IAU constellations, famous asterisms, historical (dropped) constellations, and
/// the sky as other cultures drew it. A segmented control switches collection; each
/// row shows a live stick-figure thumbnail, and tapping opens a detail page that
/// renders the figure large over its real catalog stars (sized by magnitude,
/// coloured by temperature), with curated lore.
struct ConstellationsView: View {
    let store: StarCatalogStore
    @State private var query = ""
    @State private var category: FigureCatalog = .constellations
    @State private var figures: [SkyFigure] = []
    /// Which cultural traditions are expanded. Cultural sections are collapsible
    /// dropdowns so the eight skies don't unfurl into one long list.
    @State private var expandedCultures: Set<String> = []

    /// Geometry merged so a constellation drawn as several features (Serpens) is a
    /// single set of polylines.
    private func mergedGeometry() -> [String: [[SIMD2<Double>]]] {
        var byAbbr: [String: [[SIMD2<Double>]]] = [:]
        for c in store.constellations {
            byAbbr[c.id, default: []].append(contentsOf: c.polylines)
        }
        return byAbbr
    }

    private func rebuild() {
        guard !store.constellations.isEmpty else { return }
        figures = SkyFigureLibrary.build(constellationGeometry: mergedGeometry(),
                                         catalog: store.catalog)
    }

    /// Figures in the chosen category that match the search query.
    private var filtered: [SkyFigure] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return figures.filter { fig in
            guard q.isEmpty else {
                return fig.name.lowercased().contains(q)
                    || fig.meaning.lowercased().contains(q)
                    || fig.group.lowercased().contains(q)
                    || (fig.genitive ?? "").lowercased().contains(q)
            }
            return fig.catalog == category
        }
    }

    /// Filtered figures grouped into sections. Constellations group by family in
    /// catalogue order; the other collections group by their `group` field.
    private var sections: [(title: String, items: [SkyFigure])] {
        let grouped = Dictionary(grouping: filtered, by: { $0.group })
        let order: [String]
        if isSearching {
            order = grouped.keys.sorted()
        } else if category == .constellations {
            order = ConstellationCatalog.familyOrder
        } else if category == .cultural {
            order = SkyFigureLibrary.cultureOrder
        } else {
            order = grouped.keys.sorted()
        }
        return order.compactMap { key in
            guard let items = grouped[key], !items.isEmpty else { return nil }
            return (key, items.sorted { $0.name < $1.name })
        }
    }

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack {
            Theme.spaceGradient.ignoresSafeArea()
            if figures.isEmpty {
                ProgressView().tint(.white)
            } else {
                List {
                    if !isSearching {
                        header
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 10, trailing: 0))
                    }
                    ForEach(sections, id: \.title) { section in
                        if category == .cultural && !isSearching {
                            // Each tradition is a collapsible dropdown.
                            Section {
                                DisclosureGroup(isExpanded: cultureBinding(section.title)) {
                                    ForEach(section.items) { figure in figureLink(figure) }
                                } label: {
                                    Text(section.title)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                }
                                .listRowBackground(Color.white.opacity(0.04))
                                .tint(Theme.accent)
                            }
                        } else {
                            Section {
                                ForEach(section.items) { figure in figureLink(figure) }
                            } header: {
                                Text(section.title).foregroundStyle(Theme.accent.opacity(0.9))
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Constellations")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search every figure…")
        .task(id: store.catalog?.count ?? 0) { rebuild() }
        .onAppear(perform: rebuild)
    }

    /// The collection picker plus a one-line description of the current collection.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Collection", selection: $category) {
                ForEach(FigureCatalog.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(category.caption)
                .font(.caption).foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 2)
        }
    }

    private func figureLink(_ figure: SkyFigure) -> some View {
        NavigationLink {
            SkyFigureDetailView(figure: figure, store: store)
        } label: {
            SkyFigureRow(figure: figure)
        }
        .listRowBackground(Color.white.opacity(0.04))
    }

    private func cultureBinding(_ culture: String) -> Binding<Bool> {
        Binding(
            get: { expandedCultures.contains(culture) },
            set: { isOpen in
                if isOpen { expandedCultures.insert(culture) } else { expandedCultures.remove(culture) }
            })
    }
}

// MARK: - List row

private struct SkyFigureRow: View {
    let figure: SkyFigure

    var body: some View {
        HStack(spacing: 14) {
            ConstellationFigure(polylines: figure.polylines, stars: [],
                                lineColor: Theme.accent, lineWidth: 1, glow: false)
                .frame(width: 64, height: 64)
                .background(Circle().fill(.white.opacity(0.03)))
                .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                Text(figure.name)
                    .font(.headline).foregroundStyle(.white)
                Text(figure.meaning)
                    .font(.subheadline).foregroundStyle(.white.opacity(0.6))
                if let hemisphere = figure.hemisphere {
                    Text(hemisphere.rawValue + " sky")
                        .font(.caption).foregroundStyle(.white.opacity(0.4))
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail

private struct SkyFigureDetailView: View {
    let figure: SkyFigure
    let store: StarCatalogStore
    @State private var show3D = false

    /// Catalog stars within the figure's patch of sky, brightest first, trimmed to
    /// naked-eye visibility. Region-based (not constellation-keyed) so asterisms
    /// that span several constellations still show their full star field.
    private var stars: [FigureStar] {
        guard let catalog = store.catalog else { return [] }
        let region = SkyRegion(polylines: figure.polylines)
        return catalog.stars
            .filter { $0.apparentMagnitude <= 6.5 && region.contains($0.equatorial) }
            .sorted { $0.apparentMagnitude < $1.apparentMagnitude }
            .map { star in
                FigureStar(
                    point: SIMD2(star.equatorial.rightAscension.degrees,
                                 star.equatorial.declination.degrees),
                    magnitude: star.apparentMagnitude,
                    color: StarColor.from(colorIndex: star.colorIndex),
                    label: star.properName)
            }
    }

    private var brightest: Star? {
        guard let catalog = store.catalog else { return nil }
        let region = SkyRegion(polylines: figure.polylines)
        return catalog.stars
            .filter { region.contains($0.equatorial) }
            .min { $0.apparentMagnitude < $1.apparentMagnitude }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                figureCard
                view3DButton
                header
                factCard
                Text(figure.blurb)
                    .font(.body).foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
        }
        .background(Theme.spaceGradient.ignoresSafeArea())
        .navigationTitle(figure.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $show3D) {
            Constellation3DView(figure: figure, store: store)
                .preferredColorScheme(.dark)
        }
    }

    /// Launches the rotatable 3D view, where the figure's stars sit at their real
    /// distances and the flat pattern reveals itself as a line-of-sight illusion.
    private var view3DButton: some View {
        Button { show3D = true } label: {
            Label("View in 3D", systemImage: "rotate.3d")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(LuminousButtonStyle(tint: Theme.accent))
    }

    private var figureCard: some View {
        ConstellationFigure(polylines: figure.polylines, stars: stars,
                            lineColor: Theme.accent, lineWidth: 1.4, glow: true)
            .frame(height: 300)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.panelRadius)
                    .fill(LinearGradient(colors: [Color(red: 0.02, green: 0.03, blue: 0.09),
                                                  Color(red: 0.01, green: 0.01, blue: 0.04)],
                                         startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: Theme.panelRadius)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(figure.name)
                .font(.system(.largeTitle, design: .serif).weight(.bold))
                .foregroundStyle(.white)
            Text(figure.meaning)
                .font(.title3).foregroundStyle(Theme.accent.opacity(0.9))
        }
    }

    private var factCard: some View {
        VStack(spacing: 0) {
            DetailFactRow("Collection", figure.catalog.heading)
            if let genitive = figure.genitive { DetailFactRow("Genitive", genitive) }
            DetailFactRow(figure.catalog == .constellations ? "Family" : "Group", figure.group)
            if let hemisphere = figure.hemisphere {
                DetailFactRow("Hemisphere", hemisphere.rawValue)
            }
            if let b = brightest {
                DetailFactRow("Brightest star", StarFacts.displayName(for: b)
                    + String(format: " · mag %.1f", b.apparentMagnitude))
            }
            DetailFactRow("Stars in view", "\(stars.count) to naked eye")
        }
        .luminousSurface(Theme.accent)
    }
}

private struct DetailFactRow: View {
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

/// The patch of sky a figure occupies: a centre direction and an angular radius
/// covering all its vertices (plus a margin). Used to pull just the nearby catalog
/// stars for the detail view, working for figures that span many constellations.
struct SkyRegion {
    private let center: SIMD3<Double>
    private let cosRadius: Double

    init(polylines: [[SIMD2<Double>]], marginDegrees: Double = 4) {
        let points = polylines.flatMap { $0 }
        var sum = SIMD3<Double>(repeating: 0)
        for p in points { sum += Self.unit(p) }
        center = simd_length(sum) < 1e-9 ? SIMD3(0, 0, 1) : simd_normalize(sum)
        var minDot = 1.0
        for p in points { minDot = min(minDot, simd_dot(Self.unit(p), center)) }
        let radius = acos(max(-1, min(1, minDot))) + marginDegrees * .pi / 180
        cosRadius = cos(min(.pi, radius))
    }

    func contains(_ eq: EquatorialCoordinates) -> Bool {
        let v = Self.unit(SIMD2(eq.rightAscension.degrees, eq.declination.degrees))
        return simd_dot(v, center) >= cosRadius
    }

    private static func unit(_ p: SIMD2<Double>) -> SIMD3<Double> {
        let ra = p.x * .pi / 180, dec = p.y * .pi / 180
        return SIMD3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))
    }
}

// MARK: - Figure rendering

/// A drawable star within a constellation figure: its sky position, brightness,
/// colour and optional name.
struct FigureStar {
    let point: SIMD2<Double>   // (rightAscension°, declination°)
    let magnitude: Double
    let color: Color
    let label: String?
}

/// Renders a sky figure's stick figure (and, optionally, its catalog stars and
/// labels) into a Canvas. Sky positions are flattened with a stereographic projection
/// centred on the figure, so each figure is shown undistorted and framed to
/// fit, with east to the left and north up — the convention of a printed sky chart.
struct ConstellationFigure: View {
    let polylines: [[SIMD2<Double>]]
    var stars: [FigureStar] = []
    var lineColor: Color = .white
    var lineWidth: CGFloat = 1
    var glow: Bool = false

    var body: some View {
        Canvas { context, size in
            let projection = StereographicProjection(points: polylines.flatMap { $0 })
            guard let bounds = projection.screenBounds(of: polylines.flatMap { $0 }) else { return }

            let pad: CGFloat = glow ? 28 : 8
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: pad, dy: pad)
            let scale = min(rect.width / max(bounds.width, 1e-6),
                            rect.height / max(bounds.height, 1e-6))
            let center = CGPoint(x: bounds.midX, y: bounds.midY)

            func place(_ p: SIMD2<Double>) -> CGPoint? {
                guard let s = projection.screenPoint(p) else { return nil }
                return CGPoint(x: rect.midX + (s.x - center.x) * scale,
                               y: rect.midY + (s.y - center.y) * scale)
            }

            // Background catalog stars (detail view only): glow then core.
            for star in stars {
                guard let pt = place(star.point) else { continue }
                let r = starRadius(star.magnitude)
                if glow {
                    context.fill(Path(ellipseIn: CGRect(x: pt.x - r * 2.4, y: pt.y - r * 2.4,
                                                        width: r * 4.8, height: r * 4.8)),
                                 with: .color(star.color.opacity(0.18)))
                }
                context.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r,
                                                    width: r * 2, height: r * 2)),
                             with: .color(star.color))
            }

            // Stick figure lines.
            var path = Path()
            for line in polylines {
                var started = false
                for p in line {
                    guard let pt = place(p) else { started = false; continue }
                    if started { path.addLine(to: pt) } else { path.move(to: pt); started = true }
                }
            }
            if glow {
                context.stroke(path, with: .color(lineColor.opacity(0.25)),
                               style: StrokeStyle(lineWidth: lineWidth * 3, lineCap: .round, lineJoin: .round))
            }
            context.stroke(path, with: .color(lineColor.opacity(glow ? 0.85 : 0.7)),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

            // Labels for the brightest named stars (detail view only).
            if glow {
                for star in stars.filter({ $0.label != nil }).prefix(6) {
                    guard let pt = place(star.point) else { continue }
                    let text = Text(star.label!).font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    context.draw(text, at: CGPoint(x: pt.x + 8, y: pt.y - 8), anchor: .bottomLeading)
                }
            }
        }
    }

    /// Pixel radius for a star core, scaled by apparent magnitude (brighter = larger).
    private func starRadius(_ magnitude: Double) -> CGFloat {
        let r = 3.4 - magnitude * 0.42
        return max(0.6, min(5.0, r))
    }
}

/// A stereographic projection centred on a set of sky points. Conformal and stable
/// across wide fields, so it frames both a tiny constellation (Crux) and a sprawling
/// one (Hydra, 100°+ across) without the runaway distortion a gnomonic projection
/// would suffer near its edge. Output screen coordinates already have east to the
/// left and north up.
struct StereographicProjection {
    private let ra0: Double   // tangent point, radians
    private let dec0: Double

    init(points: [SIMD2<Double>]) {
        var v = SIMD3<Double>(repeating: 0)
        for p in points {
            let ra = p.x * .pi / 180, dec = p.y * .pi / 180
            v += SIMD3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))
        }
        if simd_length(v) < 1e-9 { v = SIMD3(0, 0, 1) }
        v = simd_normalize(v)
        ra0 = atan2(v.y, v.x)
        dec0 = asin(max(-1, min(1, v.z)))
    }

    /// Projects a sky point to screen coordinates (east left, north up), or nil if
    /// it lies essentially at the antipode of the tangent point.
    func screenPoint(_ p: SIMD2<Double>) -> CGPoint? {
        let ra = p.x * .pi / 180, dec = p.y * .pi / 180
        let cosc = sin(dec0) * sin(dec) + cos(dec0) * cos(dec) * cos(ra - ra0)
        let denom = 1 + cosc
        guard denom > 1e-4 else { return nil }
        let k = 2 / denom
        let x = k * cos(dec) * sin(ra - ra0)
        let y = k * (cos(dec0) * sin(dec) - sin(dec0) * cos(dec) * cos(ra - ra0))
        // East to the left, north up (screen y grows downward).
        return CGPoint(x: -x, y: -y)
    }

    /// The bounding box of a set of points in screen coordinates, or nil if none
    /// project in front of the tangent plane.
    func screenBounds(of points: [SIMD2<Double>]) -> CGRect? {
        var minX = Double.greatestFiniteMagnitude, minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
        var any = false
        for p in points {
            guard let s = screenPoint(p) else { continue }
            any = true
            minX = min(minX, s.x); maxX = max(maxX, s.x)
            minY = min(minY, s.y); maxY = max(maxY, s.y)
        }
        guard any else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Maps a B−V colour index to an approximate star colour, mirroring the sky view's
/// palette so the same star looks the same wherever it's drawn.
enum StarColor {
    static func from(colorIndex bv: Double?) -> Color {
        guard let bv else { return Color(white: 0.95) }
        switch bv {
        case ..<0.0:  return Color(red: 0.70, green: 0.78, blue: 1.0)   // blue-white
        case 0.0..<0.3: return Color(red: 0.85, green: 0.90, blue: 1.0) // white
        case 0.3..<0.6: return Color(red: 1.0, green: 0.98, blue: 0.92) // yellow-white
        case 0.6..<1.0: return Color(red: 1.0, green: 0.92, blue: 0.75) // yellow
        case 1.0..<1.5: return Color(red: 1.0, green: 0.82, blue: 0.62) // orange
        default:        return Color(red: 1.0, green: 0.72, blue: 0.58) // red
        }
    }
}
