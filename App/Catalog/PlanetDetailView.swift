import SwiftUI
import CelestialCore

/// A full astrophysical detail sheet for a single planet — the exoplanet/solar-body
/// equivalent of the star detail page. Raw orbital and physical figures up top, then
/// the relatable "what's it like there" comparisons, host-star context, and moons.
struct PlanetDetailView: View {
    let planet: Exoplanet
    let system: PlanetarySystem
    @Environment(\.dismiss) private var dismiss

    private var facts: [String] { PlanetFacts.relatableFacts(for: planet, in: system) }

    var body: some View {
        ZStack {
            Theme.spaceGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    dataCard
                    if !facts.isEmpty { comparisons }
                    hostCard
                    if !planet.moons.isEmpty { moonsCard }
                }
                .padding()
                .padding(.bottom, 40)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.title2)
                    .foregroundStyle(.white.opacity(0.5)).padding()
            }
            .buttonStyle(.plain).accessibilityLabel("Close")
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 12) {
            LuminousGlyph(symbol: glyph, tint: tint, size: 96, glyphSize: 42)
            Text(planet.name).font(.system(.largeTitle, design: .serif).weight(.bold))
                .foregroundStyle(.white).multilineTextAlignment(.center)
            Text(planet.classification).font(.subheadline).foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 28)
    }

    private var dataCard: some View {
        VStack(spacing: 0) {
            if let r = planet.radiusEarth { row("Radius", String(format: "%.2f R⊕", r)) }
            if let m = planet.massEarth { row("Mass", String(format: "%.2f M⊕", m)) }
            if let a = system.semiMajorAxis(of: planet) { row("Orbit radius", String(format: "%.3f AU", a)) }
            if let p = planet.periodDays { row("Orbital period", periodText(p)) }
            if let e = planet.eccentricity { row("Eccentricity", String(format: "%.3f", e)) }
            if let t = planet.equilibriumTempK {
                row("Temperature", String(format: "%.0f K · %.0f°C", t, Astrophysics.celsius(fromKelvin: t)))
            }
        }
        .luminousSurface(tint)
    }

    private var comparisons: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(facts, id: \.self) { fact in
                Label(fact, systemImage: "sparkle")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hostCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Host star", systemImage: "sun.max.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            VStack(spacing: 0) {
                row("Star", system.hostName)
                if system.starCount > 1 { row("System", "\(system.starCount) stars") }
                if let s = system.spectralType { row("Spectral type", s) }
                if let t = system.stellarTempK { row("Temperature", String(format: "≈ %.0f K", t)) }
                if let l = system.luminositySun { row("Luminosity", String(format: "%@ L☉", lum(l))) }
                if let ly = system.distanceLightYears { row("Distance", String(format: "%.0f ly", ly)) }
            }
            .luminousSurface(.yellow)
        }
    }

    private var moonsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Major moons", systemImage: "moon.circle")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            VStack(spacing: 0) {
                ForEach(planet.moons) { moon in
                    row(moon.name, String(format: "%.0f km radius · %.1f-day orbit", moon.radiusKm, moon.periodDays))
                }
            }
            .luminousSurface(Color(white: 0.7))
        }
    }

    // MARK: Helpers

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value).foregroundStyle(.white).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.horizontal, 14).padding(.vertical, 11)
        .overlay(Divider().background(.white.opacity(0.08)), alignment: .bottom)
    }

    private func periodText(_ p: Double) -> String {
        p < 1 ? String(format: "%.1f h", p * 24)
              : p < 600 ? String(format: "%.1f days", p)
                        : String(format: "%.2f yr", p / 365.25)
    }

    private func lum(_ l: Double) -> String { l >= 100 ? String(format: "%.0f", l) : String(format: "%.2f", l) }

    private var tint: Color {
        switch planet.kind {
        case .rocky: Color(red: 0.80, green: 0.72, blue: 0.62)
        case .neptunian: Color(red: 0.45, green: 0.75, blue: 0.95)
        case .giant: Color(red: 0.92, green: 0.74, blue: 0.50)
        case .unknown: Color(white: 0.7)
        }
    }

    private var glyph: String {
        switch planet.kind {
        case .rocky: "globe.americas.fill"
        case .neptunian, .giant: "circle.circle.fill"
        case .unknown: "circle.dashed"
        }
    }
}
