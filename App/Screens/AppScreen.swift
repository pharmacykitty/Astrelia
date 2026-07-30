import SwiftUI

/// The app's destinations, reached from the sky view's dock. (The old full-screen
/// menu was replaced by the in-sky destination dock on 2026-07-28 — the sky is the
/// app; everything else is an overlay on it.)
enum AppScreen: Hashable, CaseIterable, Identifiable {
    case tonight, catalog, constellations, galaxyMap, about

    var id: Self { self }

    var title: String {
        switch self {
        case .tonight: "Tonight"
        case .catalog: "Catalog"
        case .constellations: "Figures"
        case .galaxyMap: "Galaxy"
        case .about: "About"
        }
    }

    var subtitle: String {
        switch self {
        case .tonight: "Moon phase, planets & meteor showers up now"
        case .catalog: "Search stars, planets & deep-sky objects"
        case .constellations: "The 88, plus asterisms, lost & cultural figures"
        case .galaxyMap: "Fly through the galaxy in 3D"
        case .about: "Data sources, credits & licenses"
        }
    }

    var symbol: String {
        switch self {
        case .tonight: "sparkles"
        case .catalog: "binoculars.fill"
        case .constellations: "point.3.connected.trianglepath.dotted"
        case .galaxyMap: "globe.americas.fill"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .tonight: .indigo
        case .catalog: .cyan
        case .constellations: Theme.accent
        case .galaxyMap: .purple
        case .about: .gray
        }
    }
}
