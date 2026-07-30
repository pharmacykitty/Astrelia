import SwiftUI
import CelestialCore

/// Visual "how does it compare?" widgets for a star's detail page. These turn the
/// catalog's raw numbers into intuition the way prose can't: where this star sits
/// among all stars (HR diagram) and how its true size stacks up against the Sun.

// MARK: - HR diagram

/// One plotted star: effective temperature (K) and luminosity (L☉).
struct HRPoint: Hashable {
    let temperatureK: Double
    let luminositySolar: Double
}

/// A Hertzsprung–Russell diagram — temperature (hot on the left, the astronomers'
/// convention) against luminosity on a log scale — with a faint background cloud of
/// catalogued stars and the selected star marked "you are here". Instantly shows
/// whether a star is a main-sequence dwarf, a giant, or a white dwarf without any
/// jargon: the eye reads the shape.
struct HRDiagramView: View {
    let population: [HRPoint]
    let highlight: HRPoint?

    // Plot bounds. Temperature axis runs hot→cool (reversed); luminosity is log10.
    private let tHot = 30_000.0, tCool = 2_500.0
    private let logLumMin = -4.0, logLumMax = 6.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Where it sits among the stars", systemImage: "chart.dots.scatter")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))

            Canvas { ctx, size in
                let plot = CGRect(x: 6, y: 6, width: size.width - 12, height: size.height - 12)

                // The main sequence runs diagonally from hot-bright to cool-faint;
                // the background cloud reveals it. Faint dots keep it a backdrop.
                for p in population {
                    guard let pt = position(p, in: plot) else { continue }
                    let c = TemperatureColor.color(forKelvin: p.temperatureK)
                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 1, y: pt.y - 1, width: 2, height: 2)),
                             with: .color(c.opacity(0.35)))
                }

                // "You are here": a haloed dot the eye jumps to.
                if let h = highlight, let pt = position(h, in: plot) {
                    let c = TemperatureColor.color(forKelvin: h.temperatureK)
                    ctx.drawLayer { layer in
                        layer.blendMode = .plusLighter
                        layer.fill(Path(ellipseIn: CGRect(x: pt.x - 9, y: pt.y - 9, width: 18, height: 18)),
                                   with: .radialGradient(Gradient(colors: [c.opacity(0.8), .clear]),
                                                         center: pt, startRadius: 0, endRadius: 9))
                    }
                    ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)),
                               with: .color(.white), lineWidth: 1.5)
                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2.5, y: pt.y - 2.5, width: 5, height: 5)),
                             with: .color(.white))
                }
            }
            .frame(height: 170)
            .quietSurface()

            HStack {
                Text("← hotter").font(.caption2).foregroundStyle(Theme.textTertiary)
                Spacer()
                Text("more luminous ↑").font(.caption2).foregroundStyle(Theme.textTertiary)
                Spacer()
                Text("cooler →").font(.caption2).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func position(_ p: HRPoint, in rect: CGRect) -> CGPoint? {
        guard p.temperatureK > 0, p.luminositySolar > 0 else { return nil }
        // x: hot (left) → cool (right), on a log temperature scale.
        let lt = log10(max(tCool, min(tHot, p.temperatureK)))
        let fx = (log10(tHot) - lt) / (log10(tHot) - log10(tCool))
        // y: faint (bottom) → luminous (top), log10 luminosity.
        let ll = max(logLumMin, min(logLumMax, log10(p.luminositySolar)))
        let fy = (ll - logLumMin) / (logLumMax - logLumMin)
        return CGPoint(x: rect.minX + fx * rect.width, y: rect.maxY - fy * rect.height)
    }
}

// MARK: - Size comparison

/// True-relative size comparison between the Sun and a star, scaled so the larger
/// of the two fills the frame. A red supergiant turns the Sun into a speck; a white
/// dwarf shrinks beside it — the most visceral way to feel a derived radius. The
/// smaller body is clamped to a visible minimum so it never disappears entirely.
struct StarSizeView: View {
    let starName: String
    let radiusSolar: Double
    var temperatureK: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Size next to the Sun", systemImage: "circle.circle")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))

            Canvas { ctx, size in
                let maxDiameter = min(size.width * 0.42, size.height * 0.9)
                let larger = max(radiusSolar, 1)
                let scale = maxDiameter / larger
                let sunD = max(3, 1 * scale)
                let starD = max(3, radiusSolar * scale)

                let sunCenter = CGPoint(x: size.width * 0.26, y: size.height * 0.5)
                let starCenter = CGPoint(x: size.width * 0.72, y: size.height * 0.5)

                disc(ctx, center: sunCenter, diameter: sunD,
                     color: TemperatureColor.color(forKelvin: Astrophysics.solarEffectiveTemperatureK))
                disc(ctx, center: starCenter, diameter: starD,
                     color: TemperatureColor.color(forKelvin: temperatureK ?? 4_000))
            }
            .frame(height: 150)
            .quietSurface()

            HStack {
                Text("Sun · 1 R☉").frame(maxWidth: .infinity)
                Text("\(starName) · ≈ \(radiusLabel) R☉").frame(maxWidth: .infinity)
            }
            .font(.caption2).foregroundStyle(Theme.textSecondary)
        }
    }

    private var radiusLabel: String {
        if radiusSolar >= 100 { return String(format: "%.0f", radiusSolar) }
        if radiusSolar >= 10 { return String(format: "%.0f", radiusSolar) }
        return String(format: "%.1f", radiusSolar)
    }

    private func disc(_ ctx: GraphicsContext, center: CGPoint, diameter: Double, color: Color) {
        let r = diameter / 2
        let frame = CGRect(x: center.x - r, y: center.y - r, width: diameter, height: diameter)
        var layer = ctx
        layer.blendMode = .plusLighter
        layer.fill(Path(ellipseIn: frame.insetBy(dx: -r * 0.4, dy: -r * 0.4)),
                   with: .radialGradient(Gradient(colors: [color.opacity(0.5), .clear]),
                                         center: center, startRadius: r * 0.4, endRadius: r * 1.4))
        ctx.fill(Path(ellipseIn: frame), with: .radialGradient(
            Gradient(colors: [.white, color]), center: center, startRadius: 0, endRadius: r))
    }
}

// MARK: - Colour key

/// A compact legend explaining that a star's colour encodes its temperature —
/// blue is hot, red is cool. Makes the sky's colour coding legible at a glance for
/// anyone who doesn't already know the convention.
struct StarColorLegend: View {
    var body: some View {
        let stops: [Color] = [12_000, 8_000, 6_000, 5_000, 4_000, 3_000]
            .map { TemperatureColor.color(forKelvin: $0) }
        VStack(spacing: 4) {
            LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing)
                .frame(height: 7)
                .clipShape(Capsule())
            HStack {
                Text("hotter").foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text("star colour ≈ temperature").foregroundStyle(Theme.textTertiary)
                Spacer()
                Text("cooler").foregroundStyle(.white.opacity(0.75))
            }
            .font(.caption2)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .quietSurface()
    }
}

// MARK: - Temperature → colour

/// Maps a stellar effective temperature to an approximate display colour along the
/// blue(hot)→red(cool) sequence. A perceptual stand-in, not a calibrated blackbody.
enum TemperatureColor {
    /// One shared threshold table — display colour AND prose adjective per band —
    /// so the sky's palette and the detail pages' words can't silently drift apart
    /// (they were duplicated verbatim in `StarFacts.colourWord(forTemp:)` before).
    private static let bands: [(minKelvin: Double, color: Color, adjective: String)] = [
        (10_000, Color(red: 0.66, green: 0.74, blue: 1.0), "a blue-white"),    // O/B
        (7_500,  Color(red: 0.82, green: 0.86, blue: 1.0), "a white"),         // A
        (6_000,  Color(red: 1.0,  green: 0.98, blue: 0.92), "a yellow-white"), // F
        (5_200,  Color(red: 1.0,  green: 0.95, blue: 0.74), "a yellow"),       // G
        (3_700,  Color(red: 1.0,  green: 0.80, blue: 0.55), "an orange"),      // K
        (-.infinity, Color(red: 1.0, green: 0.60, blue: 0.45), "a red"),       // M
    ]

    static func color(forKelvin k: Double) -> Color {
        bands.first { k >= $0.minKelvin }!.color
    }

    /// Colour adjective (with article) for prose, e.g. "an orange" star.
    static func adjective(forKelvin k: Double) -> String {
        bands.first { k >= $0.minKelvin }!.adjective
    }
}
