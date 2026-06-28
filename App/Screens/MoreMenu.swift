import SwiftUI

/// The navigation hub, presented full-screen from the sky view's menu button.
/// Full-screen (not a sheet) so pushed destinations like the Galaxy Map are
/// edge-to-edge immersive with no card gap revealing the sky behind.
struct MoreMenuView: View {
    let store: StarCatalogStore
    let exo: ExoplanetStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                MenuBackground()
                ScrollView {
                    VStack(spacing: 30) {
                        header
                        section("Explore", [.tonight, .catalog, .constellations, .galaxyMap])
                        section("Interpret", [.astrology])
                        section(nil, [.about])
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    CircleIconButton(label: "Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 26))
                .foregroundStyle(LinearGradient(colors: [.white, .purple.opacity(0.8)],
                                                startPoint: .top, endPoint: .bottom))
                .accessibilityHidden(true)
            Text("Astrolabe")
                .font(.system(.largeTitle, design: .serif)).bold()
                .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.65)],
                                                startPoint: .top, endPoint: .bottom))
            Text("Chart the heavens")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func section(_ title: String?, _ screens: [AppScreen]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.leading, 6)
            }
            ForEach(screens, id: \.self) { screen in
                NavigationLink {
                    destination(screen)
                } label: {
                    DestinationCard(screen: screen)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func destination(_ screen: AppScreen) -> some View {
        switch screen {
        case .tonight: TonightView()
        case .catalog: CatalogView(store: store, exo: exo)
        case .constellations: ConstellationsView(store: store)
        case .galaxyMap: GalaxyMapView(store: store, exo: exo)
        case .astrology: AstrologyHomeView(store: store)
        case .about: AboutView()
        }
    }
}

/// A tappable card for one destination — a luminous ringed glyph, title, subtitle,
/// with the card itself rimmed and glowing in the feature's tint.
private struct DestinationCard: View {
    let screen: AppScreen

    var body: some View {
        HStack(spacing: 16) {
            LuminousGlyph(symbol: screen.symbol, tint: screen.tint, size: 58, glyphSize: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(screen.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(screen.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(screen.tint.opacity(0.6))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(screen.tint.opacity(0.05))
                // A faint themed sky-figure peeking from the trailing edge — the
                // "star-chart card" motif that gives each destination its own sky.
                Image(systemName: screen.watermark)
                    .font(.system(size: 78, weight: .regular))
                    .foregroundStyle(screen.tint.opacity(0.10))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(x: 12)
            }
        }
        // Clip the whole card (background + watermark) so nothing bleeds onto its
        // neighbours, then draw the rim and glow on top.
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.panelRadius)
                .strokeBorder(screen.tint.opacity(0.32), lineWidth: 1)
        }
        .shadow(color: screen.tint.opacity(0.18), radius: 9)
    }
}

/// A circular glyph in the luminous-instrument language: a tinted ring and soft
/// glow around a symbol, over a near-transparent wash. Shared by the menu cards
/// and the placeholder/detail headers so they read as one family.
struct LuminousGlyph: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 52
    var glyphSize: CGFloat = 21

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: glyphSize, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background {
                Circle().fill(.ultraThinMaterial)
                Circle().fill(tint.opacity(0.12))
            }
            .overlay { Circle().strokeBorder(tint.opacity(0.55), lineWidth: 1) }
            .shadow(color: tint.opacity(0.45), radius: size * 0.18)
    }
}

/// Deep-space gradient with a faint static starfield, shared by the menu.
private struct MenuBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.04, blue: 0.12),
                                    Color(red: 0.02, green: 0.02, blue: 0.06)],
                           startPoint: .top, endPoint: .bottom)
            Canvas { context, size in
                var rng = SeededGenerator(seed: 7)
                for _ in 0..<140 {
                    let x = Double.random(in: 0...size.width, using: &rng)
                    let y = Double.random(in: 0...size.height, using: &rng)
                    let r = Double.random(in: 0.3...1.4, using: &rng)
                    let opacity = Double.random(in: 0.05...0.5, using: &rng)
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                                 with: .color(.white.opacity(opacity)))
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// A tiny deterministic LCG so the decorative starfield is stable across redraws.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

/// The future top-level screens. Real content arrives later.
enum AppScreen: Hashable, CaseIterable {
    case tonight, catalog, constellations, galaxyMap, astrology, about

    var title: String {
        switch self {
        case .tonight: "Tonight"
        case .catalog: "Catalog"
        case .constellations: "Constellations"
        case .galaxyMap: "Galaxy Map"
        case .astrology: "Astrology"
        case .about: "About"
        }
    }

    var subtitle: String {
        switch self {
        case .tonight: "Moon phase, planets & meteor showers up now"
        case .catalog: "Search stars, planets & deep-sky objects"
        case .constellations: "The 88, plus asterisms, lost & cultural figures"
        case .galaxyMap: "Fly through the galaxy in 3D"
        case .astrology: "Charts, zodiac & transits"
        case .about: "Data sources, credits & licenses"
        }
    }

    var symbol: String {
        switch self {
        case .tonight: "sparkles"
        case .catalog: "binoculars.fill"
        case .constellations: "point.3.connected.trianglepath.dotted"
        case .galaxyMap: "globe.americas.fill"
        case .astrology: "moon.stars.fill"
        case .about: "info.circle.fill"
        }
    }

    /// A large, faint sky-figure drawn behind each menu card (Proposal C motif).
    var watermark: String {
        switch self {
        case .tonight: "moon.stars.fill"
        case .catalog: "sparkles"
        case .constellations: "point.3.connected.trianglepath.dotted"
        case .galaxyMap: "hurricane"
        case .astrology: "moon.stars.fill"
        case .about: "book.closed.fill"
        }
    }

    var tint: Color {
        switch self {
        case .tonight: .indigo
        case .catalog: .cyan
        case .constellations: Theme.accent
        case .galaxyMap: .purple
        case .astrology: .yellow
        case .about: .gray
        }
    }

    var gradient: [Color] {
        switch self {
        case .tonight: [Color(red: 0.45, green: 0.5, blue: 0.95), Color(red: 0.25, green: 0.25, blue: 0.6)]
        case .catalog: [Color(red: 0.2, green: 0.8, blue: 0.95), Color(red: 0.1, green: 0.45, blue: 0.9)]
        case .constellations: [Color(red: 0.56, green: 0.72, blue: 1.0), Color(red: 0.32, green: 0.45, blue: 0.85)]
        case .galaxyMap: [Color(red: 0.6, green: 0.35, blue: 0.95), Color(red: 0.35, green: 0.2, blue: 0.7)]
        case .astrology: [Color(red: 0.98, green: 0.8, blue: 0.35), Color(red: 0.95, green: 0.5, blue: 0.3)]
        case .about: [Color(white: 0.55), Color(white: 0.32)]
        }
    }
}

/// Temporary "coming soon" screen shared by every not-yet-built section.
struct PlaceholderScreen: View {
    let screen: AppScreen

    var body: some View {
        ZStack {
            Theme.spaceGradient.ignoresSafeArea()
            VStack(spacing: 16) {
                LuminousGlyph(symbol: screen.symbol, tint: screen.tint, size: 96, glyphSize: 40)
                Text(screen.title)
                    .font(.system(.largeTitle, design: .serif).weight(.bold))
                    .foregroundStyle(.white)
                Text(screen.subtitle)
                    .font(.headline).foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                Text("Coming soon")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(screen.tint.opacity(0.7))
                    .padding(.top, 4)
            }
            .padding()
        }
        .navigationTitle(screen.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    MoreMenuView(store: StarCatalogStore(), exo: ExoplanetStore())
}
