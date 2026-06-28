import SwiftUI
import CelestialCore
import Astrology

/// The shared chart readout: Big Three, the chart wheel, the positions / aspects
/// tables (tap any row for an interpretation), and — for saved charts — a link to
/// current transits. Used by both the live "Sky Now" view and saved natal charts.
struct ChartDetailView: View {
    let chart: NatalChart
    var title: String
    var subtitle: String?
    /// When set, show a link to current transits against this (natal) chart.
    var natalForTransits: NatalChart?
    /// Optional trailing toolbar content (e.g. the 3D-sphere button).
    var toolbarTrailing: AnyView?

    @State private var reading: Reading?
    private let tint = AppScreen.astrology.tint

    init(chart: NatalChart, title: String, subtitle: String? = nil,
         natalForTransits: NatalChart? = nil, toolbarTrailing: AnyView? = nil) {
        self.chart = chart
        self.title = title
        self.subtitle = subtitle
        self.natalForTransits = natalForTransits
        self.toolbarTrailing = toolbarTrailing
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                bigThree
                ChartWheel(chart: chart)
                    .frame(height: 340)
                    .padding(.horizontal, 8)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption).foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                }
                positionsCard
                aspectsCard
                if let natal = natalForTransits {
                    NavigationLink {
                        TransitsView(natal: natal, title: title)
                    } label: {
                        HubCard(symbol: "arrow.triangle.2.circlepath", title: "Transits",
                                subtitle: "How today's sky touches this chart", tint: tint)
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
            if let toolbarTrailing {
                ToolbarItem(placement: .topBarTrailing) { toolbarTrailing }
            }
        }
        .sheet(item: $reading) { ReadingSheet(reading: $0, tint: tint) }
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
                                  body: Interpretation.planetInSign(body, pos.sign))
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

    // MARK: Positions

    private var positionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("Positions")
            ForEach(chart.positions, id: \.body) { p in
                let house = chart.houses.house(of: p.longitude)
                Button {
                    reading = Reading(
                        title: "\(p.body.name) in \(p.position.sign.name)",
                        body: Interpretation.planetInSign(p.body, p.position.sign)
                            + "\n\n" + Interpretation.planetInHouse(p.body, house))
                } label: {
                    HStack {
                        Text(p.body.glyph).font(.system(size: 18)).foregroundStyle(tint).frame(width: 26)
                        Text(p.body.name).font(.subheadline).foregroundStyle(.white)
                        if p.isRetrograde {
                            Text("℞").font(.caption.weight(.bold)).foregroundStyle(.orange)
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
                Divider().overlay(.white.opacity(0.08))
            }
        }
        .padding(16)
        .luminousSurface(tint, cornerRadius: Theme.panelRadius, glow: 12)
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

/// A short interpretation, shown in a sheet when a row is tapped.
struct Reading: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

struct ReadingSheet: View {
    let reading: Reading
    let tint: Color
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.spaceGradient.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text(reading.title)
                    .font(.title2.weight(.semibold).width(.expanded))
                    .foregroundStyle(.white)
                Text(reading.body)
                    .font(.body).foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .presentationDetents([.medium])
        .presentationBackground(.black)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                .font(.title2).foregroundStyle(.white.opacity(0.5)).padding()
        }
    }
}
