import SwiftUI
import CelestialCore
import Astrology

/// The astrology hub: a live preview of today's sky (Big Three + wheel), then a
/// choice of the full live chart or saved birth charts.
struct AstrologyHomeView: View {
    var store: StarCatalogStore? = nil
    private let tint = AppScreen.astrology.tint
    @State private var model = AstrologyModel()

    var body: some View {
        ZStack {
            Theme.spaceGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    livePreview
                    NavigationLink { SkyNowView(store: store) } label: {
                        HubCard(symbol: "sparkles", title: "Sky Now",
                                subtitle: "The live chart for your location", tint: tint)
                    }
                    NavigationLink { ChartListView(store: store) } label: {
                        HubCard(symbol: "person.crop.circle", title: "Saved Charts",
                                subtitle: "Birth charts you've saved", tint: tint)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Astrology")
        .navigationBarTitleDisplayMode(.inline)
        .buttonStyle(.plain)
        .task { await model.start() }
    }

    /// Today's sky at a glance — a small chart wheel and the Big Three, so the hub
    /// rewards a look before you tap in. Updates live as the location resolves.
    private var livePreview: some View {
        VStack(spacing: 14) {
            ChartWheel(chart: model.chart)
                .frame(height: 210)
            HStack(spacing: 8) {
                bigThreeCell("Sun", model.position(.sun)?.position)
                bigThreeCell("Moon", model.position(.moon)?.position)
                bigThreeCell("Rising", ZodiacPosition(longitude: model.chart.angles.ascendant))
            }
            Text(model.locationLabel)
                .font(.caption).foregroundStyle(.white.opacity(0.45))
        }
        .padding(16)
        .luminousSurface(tint, cornerRadius: Theme.panelRadius, glow: 12)
    }

    private func bigThreeCell(_ label: String, _ pos: ZodiacPosition?) -> some View {
        VStack(spacing: 4) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold)).tracking(1.2)
                .foregroundStyle(.white.opacity(0.5))
            Text(pos?.sign.glyph ?? "–")
                .font(.title2).foregroundStyle(tint)
            Text(pos?.sign.name ?? "—")
                .font(.caption).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// A large luminous destination card, matching the main menu's language.
struct HubCard: View {
    let symbol: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(spacing: 16) {
            LuminousGlyph(symbol: symbol, tint: tint, size: 52, glyphSize: 21)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(.white)
                Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint.opacity(0.6))
        }
        .padding(16)
        .luminousSurface(tint, cornerRadius: Theme.panelRadius, glow: 12)
    }
}
