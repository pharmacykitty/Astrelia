import SwiftUI
import CelestialCore
import Astrology

/// The shared chart readout: Big Three, the chart wheel, and the positions /
/// aspects tables. Used by both the live "Sky Now" view and saved natal charts.
struct ChartDetailView: View {
    let chart: NatalChart
    var title: String
    var subtitle: String?
    /// Optional trailing toolbar content (e.g. an "edit" or "3D" button).
    var toolbarTrailing: AnyView?

    private let tint = AppScreen.astrology.tint

    init(chart: NatalChart, title: String, subtitle: String? = nil, toolbarTrailing: AnyView? = nil) {
        self.chart = chart
        self.title = title
        self.subtitle = subtitle
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
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                positionsCard
                aspectsCard
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
    }

    // MARK: Big Three

    private var bigThree: some View {
        HStack(spacing: 12) {
            cell("Sun", chart.position(of: .sun)?.position)
            cell("Moon", chart.position(of: .moon)?.position)
            cell("Rising", ZodiacPosition(longitude: chart.angles.ascendant))
        }
    }

    private func cell(_ label: String, _ pos: ZodiacPosition?) -> some View {
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

    // MARK: Positions

    private var positionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("Positions")
            ForEach(chart.positions, id: \.body) { p in
                HStack {
                    Text(p.body.glyph).font(.system(size: 18)).foregroundStyle(tint).frame(width: 26)
                    Text(p.body.name).font(.subheadline).foregroundStyle(.white)
                    if p.isRetrograde {
                        Text("℞").font(.caption.weight(.bold)).foregroundStyle(.orange)
                    }
                    Spacer()
                    Text(p.position.description)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                    Text(Self.roman(chart.houses.house(of: p.longitude)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 34, alignment: .trailing)
                }
                .padding(.vertical, 7)
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
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .font(.system(size: 17))
                    .padding(.vertical, 7)
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
