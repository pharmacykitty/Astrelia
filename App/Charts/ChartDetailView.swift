import SwiftUI
import CelestialCore
import Astrology

/// The shared chart readout: Big Three, chart-shape patterns, the wheel, the
/// chart ruler, positions (with dignities + an opt-in points/asteroids drawer)
/// and aspects — tap any row for a sectioned interpretation — plus, for saved
/// charts, a link to current transits.
struct ChartDetailView: View {
    let chart: NatalChart
    var title: String
    var subtitle: String?
    /// When set, show a link to current transits against this (natal) chart.
    var natalForTransits: NatalChart?
    /// Optional trailing toolbar content (e.g. the 3D-sphere button).
    var toolbarTrailing: AnyView?

    @State private var reading: Reading?
    @State private var extraPoints: [BodyPosition] = []
    @State private var showPoints = false
    @State private var showShareDialog = false
    @State private var shareItem: ShareItem?
    private let tint = AppScreen.astrology.tint

    init(chart: NatalChart, title: String, subtitle: String? = nil,
         natalForTransits: NatalChart? = nil, toolbarTrailing: AnyView? = nil) {
        self.chart = chart
        self.title = title
        self.subtitle = subtitle
        self.natalForTransits = natalForTransits
        self.toolbarTrailing = toolbarTrailing
    }

    private var patterns: [ChartPattern] { Patterns.detect(in: chart) }
    private var ascSign: ZodiacSign { ZodiacSign(longitude: chart.angles.ascendant) }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                bigThree
                if !patterns.isEmpty { patternChips }
                ChartWheel(chart: chart)
                    .frame(height: 340)
                    .padding(.horizontal, 8)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption).foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                }
                chartRulerCard
                elementalBalanceCard
                positionsCard
                houseRulersCard
                aspectsCard
                if let natal = natalForTransits {
                    NavigationLink {
                        TransitsView(natal: natal, title: title)
                    } label: {
                        HubCard(symbol: "arrow.triangle.2.circlepath", title: "Transits",
                                subtitle: "How today's sky touches this chart", tint: tint)
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        PredictiveView(natal: natal, title: title)
                    } label: {
                        HubCard(symbol: "calendar.badge.clock", title: "Progressions & Returns",
                                subtitle: "Your inner chart, and the year & month ahead", tint: tint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background(Theme.spaceGradient.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Share chart", systemImage: "square.and.arrow.up") { showShareDialog = true }
                    .tint(tint)
            }
            if let toolbarTrailing {
                ToolbarItem(placement: .topBarTrailing) { toolbarTrailing }
            }
        }
        .confirmationDialog("Share this chart", isPresented: $showShareDialog, titleVisibility: .visible) {
            ForEach(ShareCardStyle.allCases) { style in
                Button(style.rawValue) { shareCard(style) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url]).presentationDetents([.medium, .large])
        }
        .task(id: chart.julianDay) { loadExtraPoints() }
        .sheet(item: $reading) { ReadingSheet(reading: $0, tint: tint) }
    }

    private func shareCard(_ style: ShareCardStyle) {
        if let url = renderChartShareCard(chart: chart, title: title, subtitle: subtitle ?? "", style: style) {
            shareItem = ShareItem(url: url)
        }
    }

    // MARK: Big Three

    private var bigThree: some View {
        HStack(spacing: 12) {
            cell("Sun", .sun, chart.position(of: .sun)?.position)
            cell("Moon", .moon, chart.position(of: .moon)?.position)
            cell("Rising", nil, ZodiacPosition(longitude: chart.angles.ascendant))
        }
    }

    private func cell(_ label: String, _ body: AstroBody?, _ pos: ZodiacPosition?) -> some View {
        Button {
            guard let pos else { return }
            if let body {
                reading = Reading(title: "\(label): \(pos.sign.name)",
                                  sections: Interpretation.planetReading(
                                    body, sign: pos.sign,
                                    house: chart.houses.house(of: pos.longitude),
                                    dignity: Dignities.dignity(of: body, in: pos.sign),
                                    aspects: aspects(for: body)))
            } else {
                reading = Reading(title: "Rising: \(pos.sign.name)",
                                  body: "Your Ascendant is in \(pos.sign.name) — the mask you meet the world with. " + Interpretation.sign(pos.sign))
            }
        } label: {
            VStack(spacing: 6) {
                Text(label.uppercased())
                    .font(.caption.weight(.semibold)).tracking(1.5)
                    .foregroundStyle(.white.opacity(0.5))
                Text(pos?.sign.glyph ?? "–").font(.largeTitle).foregroundStyle(tint)
                Text(pos?.sign.name ?? "—").font(.subheadline.weight(.medium)).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .luminousSurface(tint, cornerRadius: Theme.cardRadius, glow: 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: Patterns (F1)

    private var patternChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(patterns) { p in
                    Button { reading = patternReading(p) } label: {
                        HStack(spacing: 6) {
                            Text(p.kind.glyph).foregroundStyle(tint)
                            Text(p.kind.title).font(.caption.weight(.semibold)).foregroundStyle(.white)
                            Text(p.detail).font(.caption2).foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.white.opacity(0.05), in: Capsule())
                        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func patternReading(_ p: ChartPattern) -> Reading {
        let involved = p.bodies.map(\.name).joined(separator: ", ")
        let desc: String
        switch p.kind {
        case .stellium: desc = "A cluster of bodies in one sign — a concentrated focus of energy that dominates the chart."
        case .grandTrine: desc = "Three bodies in a flowing triangle — a natural, easy talent that can be taken for granted."
        case .tSquare: desc = "An opposition squared by a third body at the apex — dynamic tension that drives achievement."
        case .grandCross: desc = "Two oppositions locked in four squares — a powerful, demanding configuration that seeks balance on all fronts."
        case .yod: desc = "A 'finger of fate' — two sextiles pointing to an apex that quincunxes both, marking a special mission to refine."
        }
        return Reading(title: p.kind.title, sections: [
            ReadingSection(title: "", body: desc),
            ReadingSection(title: "In your chart", body: "\(involved). (\(p.detail).)"),
        ])
    }

    // MARK: Chart ruler (F2)

    @ViewBuilder private var chartRulerCard: some View {
        let ruler = Dignities.chartRuler(ascendantSign: ascSign)
        if let pos = chart.position(of: ruler) {
            let house = chart.houses.house(of: pos.longitude)
            Button {
                reading = Reading(title: "Chart ruler: \(ruler.name)",
                                  sections: [ReadingSection(title: "",
                                    body: "\(ruler.name) rules your \(ascSign.name) Ascendant, so it sets the tone for the whole chart.")]
                                    + Interpretation.planetReading(ruler, sign: pos.position.sign, house: house,
                                        dignity: Dignities.dignity(of: ruler, in: pos.position.sign),
                                        retrograde: pos.isRetrograde, aspects: aspects(for: ruler)))
            } label: {
                HStack(spacing: 10) {
                    Text(ruler.glyph).font(.title3).foregroundStyle(tint).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CHART RULER").font(.caption2.weight(.semibold)).tracking(1.4)
                            .foregroundStyle(.white.opacity(0.45))
                        Text("\(ruler.name) rules your \(ascSign.name) Ascendant")
                            .font(.subheadline).foregroundStyle(.white)
                    }
                    Spacer()
                    Text("\(pos.position.description) · \(Self.roman(house))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.5))
                }
                .contentShape(Rectangle())
                .padding(16)
                .luminousSurface(tint, cornerRadius: Theme.panelRadius, glow: 12)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Elemental balance

    @ViewBuilder private var elementalBalanceCard: some View {
        let sections = Interpretation.elementalBalance(chart.positions)
        if let sec = sections.first {
            Button {
                reading = Reading(title: "Elements & balance", sections: sections)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "circle.hexagongrid.fill").foregroundStyle(tint).font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ELEMENTS & BALANCE").font(.caption2.weight(.semibold)).tracking(1.4)
                            .foregroundStyle(.white.opacity(0.45))
                        Text(sec.body).font(.subheadline).foregroundStyle(.white.opacity(0.85))
                            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .padding(16)
                .luminousSurface(tint, cornerRadius: Theme.panelRadius, glow: 12)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: House rulers

    private var houseRulersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("House rulers")
            ForEach(1...12, id: \.self) { h in
                houseRulerRow(h)
                if h < 12 { Divider().overlay(.white.opacity(0.08)) }
            }
        }
        .padding(16)
        .luminousSurface(tint, cornerRadius: Theme.panelRadius, glow: 12)
    }

    private func houseRulerRow(_ h: Int) -> some View {
        let cuspSign = ZodiacSign(longitude: chart.houses.cusp(h))
        let ruler = cuspSign.traditionalRuler
        let rulerPos = chart.position(of: ruler)
        let rulerSign = rulerPos?.position.sign ?? cuspSign
        let rulerHouse = rulerPos.map { chart.houses.house(of: $0.longitude) } ?? h
        return Button {
            reading = Reading(title: "Ruler of the \(ordinalWord(h)) house",
                body: Interpretation.houseRuler(house: h, sign: cuspSign, ruler: ruler,
                                                rulerSign: rulerSign, rulerHouse: rulerHouse))
        } label: {
            HStack(spacing: 8) {
                Text(Self.roman(h)).font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(tint).frame(width: 28, alignment: .leading)
                Text(cuspSign.glyph).font(.system(size: 15)).foregroundStyle(.white.opacity(0.75))
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.white.opacity(0.3))
                Text(ruler.glyph).font(.system(size: 15)).foregroundStyle(tint)
                Text(ruler.name).font(.subheadline).foregroundStyle(.white)
                Spacer()
                Text("in \(Self.roman(rulerHouse))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.5))
            }
            .contentShape(Rectangle())
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }

    private func ordinalWord(_ n: Int) -> String {
        ["first","second","third","fourth","fifth","sixth","seventh","eighth",
         "ninth","tenth","eleventh","twelfth"][max(0, min(11, n - 1))]
    }

    // MARK: Positions (+ dignities, + points drawer)

    private var positionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("Positions")
            ForEach(chart.positions, id: \.body) { p in
                positionRow(p, cyan: false)
                Divider().overlay(.white.opacity(0.08))
            }
            if !extraPoints.isEmpty {
                DisclosureGroup(isExpanded: $showPoints) {
                    ForEach(extraPoints, id: \.body) { p in
                        positionRow(p, cyan: true)
                        Divider().overlay(.white.opacity(0.08))
                    }
                } label: {
                    HStack {
                        Text("Points & asteroids")
                            .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text("\(extraPoints.count)").font(.caption).foregroundStyle(.white.opacity(0.4))
                    }
                    .contentShape(Rectangle())
                }
                .tint(.cyan)
                .padding(.top, 8)
            }
        }
        .padding(16)
        .luminousSurface(tint, cornerRadius: Theme.panelRadius, glow: 12)
    }

    private func positionRow(_ p: BodyPosition, cyan: Bool) -> some View {
        let house = chart.houses.house(of: p.longitude)
        let dignity = Dignities.dignity(of: p.body, in: p.position.sign)
        return Button {
            reading = Reading(
                title: "\(p.body.name) in \(p.position.sign.name)",
                sections: Interpretation.planetReading(p.body, sign: p.position.sign, house: house,
                                                       dignity: dignity, retrograde: p.isRetrograde,
                                                       aspects: aspects(for: p.body)))
        } label: {
            HStack(spacing: 6) {
                Text(p.body.glyph).font(.system(size: 18))
                    .foregroundStyle(cyan ? .cyan : tint).frame(width: 26)
                Text(p.body.name).font(.subheadline).foregroundStyle(.white)
                if p.isRetrograde {
                    Text("℞").font(.caption.weight(.bold)).foregroundStyle(.orange)
                }
                if dignity != .none {
                    Text(dignity.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(dignity.isStrong ? .green : .red.opacity(0.9))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background((dignity.isStrong ? Color.green : .red).opacity(0.12), in: Capsule())
                }
                Spacer()
                Text(p.position.description)
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.8))
                Text(Self.roman(house))
                    .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.4))
                    .frame(width: 34, alignment: .trailing)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }

    // MARK: Aspects

    private var aspectsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("Aspects")
            if chart.aspects.isEmpty {
                Text("No aspects within orb.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.5))
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(chart.aspects.enumerated()), id: \.offset) { _, a in
                    Button {
                        reading = Reading(title: "\(a.bodyA.name) \(a.kind.name) \(a.bodyB.name)",
                                          body: Interpretation.aspect(a.kind, a.bodyA, a.bodyB))
                    } label: {
                        HStack(spacing: 8) {
                            Text(a.bodyA.glyph).foregroundStyle(tint)
                            Text(a.kind.glyph).foregroundStyle(.white.opacity(0.7)).frame(width: 20)
                            Text(a.bodyB.glyph).foregroundStyle(tint)
                            Text(a.kind.name).font(.subheadline).foregroundStyle(.white)
                            if a.isApplying == true {
                                Text("applying").font(.caption2).foregroundStyle(.green.opacity(0.7))
                            }
                            Spacer()
                            Text(String(format: "%.1f°", a.orb))
                                .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.5))
                        }
                        .font(.system(size: 17))
                        .contentShape(Rectangle())
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(.white.opacity(0.08))
                }
            }
        }
        .padding(16)
        .luminousSurface(tint, cornerRadius: Theme.panelRadius, glow: 12)
    }

    // MARK: Helpers

    /// The tightest aspects a body makes in this chart, as (kind, other).
    private func aspects(for body: AstroBody) -> [(kind: AspectKind, other: AstroBody)] {
        chart.aspects.compactMap { a in
            if a.bodyA == body { return (a.kind, a.bodyB) }
            if a.bodyB == body { return (a.kind, a.bodyA) }
            return nil
        }
    }

    private func loadExtraPoints() {
        let eph = CelestialCoreEphemeris()
        extraPoints = AstroBody.points.compactMap {
            eph.position(of: $0, at: chart.julianDay, zodiac: chart.settings.zodiac)
        }
    }

    private func cardTitle(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.caption.weight(.semibold)).tracking(1.6)
            .foregroundStyle(.white.opacity(0.45))
            .padding(.bottom, 8)
    }

    static func roman(_ n: Int) -> String {
        ["I","II","III","IV","V","VI","VII","VIII","IX","X","XI","XII"][max(0, min(11, n - 1))]
    }
}

/// A short, sectioned interpretation shown in a sheet when a row is tapped.
struct Reading: Identifiable {
    let id = UUID()
    let title: String
    let sections: [ReadingSection]

    init(title: String, sections: [ReadingSection]) {
        self.title = title
        self.sections = sections
    }
    /// Convenience for a single-block reading.
    init(title: String, body: String) {
        self.init(title: title, sections: [ReadingSection(title: "", body: body)])
    }
}

struct ReadingSheet: View {
    let reading: Reading
    let tint: Color
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.spaceGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(reading.title)
                        .font(.title2.weight(.semibold).width(.expanded))
                        .foregroundStyle(.white)
                    ForEach(Array(reading.sections.enumerated()), id: \.offset) { _, sec in
                        VStack(alignment: .leading, spacing: 6) {
                            if !sec.title.isEmpty {
                                Text(sec.title.uppercased())
                                    .font(.caption.weight(.semibold)).tracking(1.4)
                                    .foregroundStyle(tint.opacity(0.85))
                            }
                            Text(sec.body)
                                .font(.body).foregroundStyle(.white.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.black)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                .font(.title2).foregroundStyle(.white.opacity(0.5)).padding()
                .accessibilityLabel("Close")
        }
    }
}
