import SwiftUI
import CelestialCore

@main
struct StellariaApp: App {
    var body: some Scene {
        WindowGroup {
            // Debug-only snapshot routes so deep screens can be captured directly
            // (the menu can't be scripted in the simulator).
            if ProcessInfo.processInfo.arguments.contains("-snapshotStar") {
                NavigationStack { StarSnapshotHarness() }
                    .preferredColorScheme(.dark)
            } else if ProcessInfo.processInfo.arguments.contains("-galaxyBH") {
                // Debug: open the Galaxy Map at Sgr A*.
                GalaxyBlackHoleHarness()
            } else if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-galaxyLandmark") {
                // Debug: open the Galaxy Map flown to a named landmark (default: Orion Nebula).
                let args = ProcessInfo.processInfo.arguments
                let name = (i + 1 < args.count && !args[i + 1].hasPrefix("-")) ? args[i + 1] : "Orion Nebula"
                GalaxyLandmarkHarness(landmarkName: name)
            } else if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-snapshotCon3D") {
                // Debug: open the 3D constellation view for a named figure (default: Orion).
                let args = ProcessInfo.processInfo.arguments
                let name = (i + 1 < args.count && !args[i + 1].hasPrefix("-")) ? args[i + 1] : "Orion"
                Constellation3DHarness(figureName: name)
            } else if ProcessInfo.processInfo.arguments.contains("-snapshotCatalog") {
                NavigationStack { CatalogSnapshotHarness() }
                    .preferredColorScheme(.dark)
            } else if ProcessInfo.processInfo.arguments.contains("-snapshotFigures") {
                NavigationStack { FiguresSnapshotHarness() }
                    .preferredColorScheme(.dark)
            } else if ProcessInfo.processInfo.arguments.contains("-snapshotAbout") {
                NavigationStack { AboutView() }
                    .preferredColorScheme(.dark)
            } else if ProcessInfo.processInfo.arguments.contains("-snapshotSettings") {
                NavigationStack { SettingsView() }
            } else if ProcessInfo.processInfo.arguments.contains("-snapshotTonight") {
                NavigationStack {
                    TonightView(fixedLocation: GeographicLocation(latitude: .degrees(40.71),
                                                                  longitude: .degrees(-74.0)))
                }
                .preferredColorScheme(.dark)
            } else if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-snapshotPlanet") {
                let args = ProcessInfo.processInfo.arguments
                let name = (i + 1 < args.count && !args[i + 1].hasPrefix("-")) ? args[i + 1] : "Earth"
                PlanetSnapshotHarness(planetName: name)
                    .preferredColorScheme(.dark)
            } else {
                ContentView()
            }
        }
    }
}

/// Debug host for `-galaxyLandmark <name>`: the Galaxy Map flown to a landmark,
/// with its own stores (the normal app path owns these in `ContentView`).
private struct GalaxyLandmarkHarness: View {
    let landmarkName: String
    @State private var store = StarCatalogStore()
    @State private var exo = ExoplanetStore()

    var body: some View {
        let landmark = Landmarks.all.first {
            $0.name.localizedCaseInsensitiveContains(landmarkName)
        } ?? Landmarks.all[0]
        GalaxyMapView(store: store, exo: exo, focus: .landmark(landmark))
            .task { store.loadIfNeeded(); exo.loadIfNeeded() }
            .preferredColorScheme(.dark)
    }
}

/// Debug host for `-snapshotCon3D <name>`: the 3D constellation view, direct.
private struct Constellation3DHarness: View {
    let figureName: String
    @State private var store = StarCatalogStore()
    @State private var figure: SkyFigure?

    var body: some View {
        let posed = ProcessInfo.processInfo.arguments.contains("-posed")
        Group {
            if let figure {
                Constellation3DView(figure: figure, store: store,
                                    debugPose: posed ? (yawOffset: 0.85, pitchOffset: 0.22, zoom: 0.45) : nil)
            } else {
                Color.black.ignoresSafeArea().overlay(ProgressView())
            }
        }
        .preferredColorScheme(.dark)
        .task {
            store.loadIfNeeded()
            while store.catalog == nil || store.constellations.isEmpty {
                try? await Task.sleep(for: .milliseconds(50))
            }
            var byAbbr: [String: [[SIMD2<Double>]]] = [:]
            for c in store.constellations {
                byAbbr[c.id, default: []].append(contentsOf: c.polylines)
            }
            let figures = SkyFigureLibrary.build(constellationGeometry: byAbbr,
                                                 catalog: store.catalog)
            figure = figures.first { $0.name.localizedCaseInsensitiveContains(figureName) }
                ?? figures.first
        }
    }
}

/// Debug host for `-snapshotCatalog`: the Catalog browse list, direct.
private struct CatalogSnapshotHarness: View {
    @State private var store = StarCatalogStore()
    @State private var exo = ExoplanetStore()

    var body: some View {
        CatalogView(store: store, exo: exo)
            .task { store.loadIfNeeded(); exo.loadIfNeeded() }
    }
}

/// Debug host for `-snapshotFigures`: the Constellations browse list, direct.
private struct FiguresSnapshotHarness: View {
    @State private var store = StarCatalogStore()

    var body: some View {
        ConstellationsView(store: store)
            .task { store.loadIfNeeded() }
    }
}

/// Debug host for `-galaxyBH`: the Galaxy Map focused on Sagittarius A*.
private struct GalaxyBlackHoleHarness: View {
    @State private var store = StarCatalogStore()
    @State private var exo = ExoplanetStore()

    var body: some View {
        GalaxyMapView(store: store, exo: exo, focus: .blackHole)
            .task { store.loadIfNeeded(); exo.loadIfNeeded() }
            .preferredColorScheme(.dark)
    }
}
