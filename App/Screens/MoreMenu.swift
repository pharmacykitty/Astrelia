import SwiftUI

/// The navigation hub, presented from the sky view's menu button. Keeps the sky
/// itself uncluttered (no persistent tab bar) while giving the not-yet-built
/// screens a home. Populate these placeholders later.
struct MoreMenuView: View {
    let store: StarCatalogStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Explore") {
                    destination(.catalog)
                    destination(.galaxyMap)
                }
                Section("Interpret") {
                    destination(.astrology)
                }
                Section {
                    destination(.about)
                }
            }
            .navigationTitle("Astrolabe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func destination(_ screen: AppScreen) -> some View {
        NavigationLink {
            switch screen {
            case .galaxyMap: GalaxyMapView(store: store)
            default: PlaceholderScreen(screen: screen)
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(screen.title)
                    Text(screen.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: screen.symbol).foregroundStyle(screen.tint)
            }
        }
    }
}

/// The future top-level screens. Real content arrives later.
enum AppScreen: CaseIterable {
    case catalog, galaxyMap, astrology, about

    var title: String {
        switch self {
        case .catalog: "Catalog"
        case .galaxyMap: "Galaxy Map"
        case .astrology: "Astrology"
        case .about: "About"
        }
    }

    var subtitle: String {
        switch self {
        case .catalog: "Search stars, planets & deep-sky objects"
        case .galaxyMap: "Fly through the galaxy in 3D"
        case .astrology: "Charts, zodiac & transits"
        case .about: "Sources, credits & settings"
        }
    }

    var symbol: String {
        switch self {
        case .catalog: "magnifyingglass"
        case .galaxyMap: "globe.americas"
        case .astrology: "moon.stars"
        case .about: "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .catalog: .cyan
        case .galaxyMap: .purple
        case .astrology: .yellow
        case .about: .gray
        }
    }
}

/// Temporary "coming soon" screen shared by every not-yet-built section.
struct PlaceholderScreen: View {
    let screen: AppScreen

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.03, green: 0.04, blue: 0.12), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: screen.symbol)
                    .font(.system(size: 52))
                    .foregroundStyle(screen.tint)
                Text(screen.title)
                    .font(.system(.largeTitle, design: .serif).weight(.bold))
                    .foregroundStyle(.white)
                Text(screen.subtitle)
                    .font(.headline).foregroundStyle(.white.opacity(0.7))
                Text("Coming soon")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 4)
            }
            .padding()
        }
        .navigationTitle(screen.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    MoreMenuView(store: StarCatalogStore())
}
