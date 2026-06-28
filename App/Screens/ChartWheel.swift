import SwiftUI
import CelestialCore
import Astrology

/// A traditional round chart wheel: the zodiac ring (12 sign sectors), the house
/// cusps, the cardinal angles, and the bodies placed at their ecliptic longitude.
/// Drawn with `Canvas` in the app's luminous-instrument language.
///
/// Orientation follows convention: the Ascendant is on the **left** (east) and
/// longitude increases **counter-clockwise**, so the MC sits near the top and the
/// IC at the bottom.
struct ChartWheel: View {
    let chart: NatalChart

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let rOuter = min(size.width, size.height) / 2 - 6
            let rZodiac = rOuter * 0.82   // inner edge of the sign ring
            let rHouse = rOuter * 0.30    // inner house circle
            let rBody = rOuter * 0.56     // radius bodies are plotted at
            let asc = chart.angles.ascendant.degrees

            // Map an ecliptic longitude to a point at the given radius.
            func point(_ lonDeg: Double, _ r: Double) -> CGPoint {
                let phi = (180.0 + (lonDeg - asc)) * .pi / 180.0
                return CGPoint(x: center.x + r * cos(phi), y: center.y - r * sin(phi))
            }

            // Concentric rings.
            for r in [rOuter, rZodiac, rHouse] {
                ctx.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(.white.opacity(0.18)), lineWidth: 1)
            }

            // Sign sectors: dividers, element tint, and glyphs.
            for sign in ZodiacSign.allCases {
                let start = sign.startLongitude.degrees
                ctx.stroke(Path { p in
                    p.move(to: point(start, rHouse))
                    p.addLine(to: point(start, rOuter))
                }, with: .color(.white.opacity(0.16)), lineWidth: 1)

                let mid = start + 15
                let glyphPoint = point(mid, (rOuter + rZodiac) / 2)
                ctx.draw(Text(sign.glyph).font(.system(size: 15)).foregroundStyle(elementColor(sign.element)),
                         at: glyphPoint)
            }

            // House cusps.
            for i in 1...12 {
                let lon = chart.houses.cusp(i).degrees
                let isAngle = (i == 1 || i == 4 || i == 7 || i == 10)
                ctx.stroke(Path { p in
                    p.move(to: point(lon, rHouse))
                    p.addLine(to: point(lon, rZodiac))
                }, with: .color(.white.opacity(isAngle ? 0.55 : 0.18)),
                   lineWidth: isAngle ? 1.6 : 0.8)

                // House number just inside the cusp.
                let numPoint = point(lon + 5, rHouse + (rBody - rHouse) * 0.18)
                ctx.draw(Text(roman(i)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.35)),
                         at: numPoint)
            }

            // Angle labels (AC / MC / DC / IC).
            label(ctx, "AC", point(asc, rOuter + 0))
            label(ctx, "DC", point(chart.angles.descendant.degrees, rOuter))
            label(ctx, "MC", point(chart.angles.midheaven.degrees, rOuter))
            label(ctx, "IC", point(chart.angles.imumCoeli.degrees, rOuter))

            // Bodies.
            for p in chart.positions {
                let pt = point(p.longitude.degrees, rBody)
                // A small luminous dot + glyph.
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4)),
                         with: .color(.yellow.opacity(0.9)))
                let glyphPoint = point(p.longitude.degrees, rBody - 16)
                ctx.draw(Text(p.body.glyph).font(.system(size: 15, weight: .medium)).foregroundStyle(.white),
                         at: glyphPoint)
            }

            // Aspect lines across the inner circle.
            for a in chart.aspects {
                guard let pa = chart.position(of: a.bodyA), let pb = chart.position(of: a.bodyB) else { continue }
                let from = point(pa.longitude.degrees, rHouse)
                let to = point(pb.longitude.degrees, rHouse)
                ctx.stroke(Path { p in p.move(to: from); p.addLine(to: to) },
                           with: .color(aspectColor(a.kind).opacity(0.5)),
                           lineWidth: a.kind.isMajor ? 1.0 : 0.5)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Chart wheel")
        .accessibilityValue("Rising \(ZodiacPosition(longitude: chart.angles.ascendant).sign.name), "
            + "\(chart.positions.count) bodies, \(chart.aspects.count) aspects")
    }

    private func label(_ ctx: GraphicsContext, _ s: String, _ at: CGPoint) {
        ctx.draw(Text(s).font(.system(size: 10, weight: .bold)).foregroundStyle(AppScreen.astrology.tint),
                 at: at)
    }

    private func roman(_ n: Int) -> String {
        ["I","II","III","IV","V","VI","VII","VIII","IX","X","XI","XII"][n - 1]
    }

    private func elementColor(_ e: ZodiacSign.Element) -> Color {
        switch e {
        case .fire: return Color(red: 1.0, green: 0.5, blue: 0.4)
        case .earth: return Color(red: 0.5, green: 0.85, blue: 0.55)
        case .air: return Color(red: 0.95, green: 0.85, blue: 0.5)
        case .water: return Color(red: 0.5, green: 0.75, blue: 1.0)
        }
    }

    private func aspectColor(_ k: AspectKind) -> Color {
        switch k {
        case .trine, .sextile: return .cyan
        case .square, .opposition: return .red
        case .conjunction: return .white
        default: return .purple
        }
    }
}
