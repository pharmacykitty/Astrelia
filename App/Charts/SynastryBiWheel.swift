import SwiftUI
import CelestialCore
import Astrology

/// A synastry **bi-wheel**: the zodiac ring with two people's planets on
/// concentric bands — person A (inner, gold) and person B (outer, rose) — and the
/// inter-chart aspects drawn as chords across the hub, coloured by harmony.
///
/// Orientation follows `ChartWheel`: person A's Ascendant sits on the left and
/// longitude increases counter-clockwise.
struct SynastryBiWheel: View {
    let inner: NatalChart          // person A
    let outer: NatalChart          // person B
    let aspects: [SynastryAspect]

    private let goldA = AppScreen.astrology.tint
    private let roseB = Color(red: 1.0, green: 0.55, blue: 0.72)

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let R = min(size.width, size.height) / 2 - 6
            let rZodiac = R * 0.84
            let rB = R * 0.72          // person B planets
            let rA = R * 0.46          // person A planets
            let rHub = R * 0.40        // aspect chords connect here
            let asc = inner.angles.ascendant.degrees

            func point(_ lonDeg: Double, _ r: Double) -> CGPoint {
                let phi = (180.0 + (lonDeg - asc)) * .pi / 180.0
                return CGPoint(x: c.x + r * cos(phi), y: c.y - r * sin(phi))
            }

            // Rings.
            for r in [R, rZodiac, R * 0.55, rHub] {
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(.white.opacity(0.16)), lineWidth: 1)
            }

            // Sign sectors + glyphs.
            for sign in ZodiacSign.allCases {
                let start = sign.startLongitude.degrees
                ctx.stroke(Path { p in
                    p.move(to: point(start, rHub)); p.addLine(to: point(start, R))
                }, with: .color(.white.opacity(0.14)), lineWidth: 1)
                let glyphPoint = point(start + 15, (R + rZodiac) / 2)
                ctx.draw(Text(sign.glyph).font(.system(size: 14)).foregroundStyle(SynastryStyle.element(sign.element)),
                         at: glyphPoint)
            }

            // Inter-chart aspect chords across the hub.
            for a in aspects {
                guard let pa = inner.position(of: a.a), let pb = outer.position(of: a.b) else { continue }
                let from = point(pa.longitude.degrees, rHub)
                let to = point(pb.longitude.degrees, rHub)
                ctx.stroke(Path { p in p.move(to: from); p.addLine(to: to) },
                           with: .color(SynastryStyle.aspect(a.kind).opacity(0.55)),
                           lineWidth: a.kind.isMajor ? 1.0 : 0.5)
            }

            // Person A planets (inner band, gold).
            drawBodies(ctx, inner.positions, radius: rA, point: point, color: goldA)
            // Person B planets (outer band, rose).
            drawBodies(ctx, outer.positions, radius: rB, point: point, color: roseB)

            // Angle labels for the inner chart.
            label(ctx, "AC", point(asc, R), goldA)
            label(ctx, "MC", point(inner.angles.midheaven.degrees, R), goldA)
        }
        .accessibilityElement()
        .accessibilityLabel("Synastry bi-wheel")
        .accessibilityValue("\(aspects.count) inter-chart aspects")
    }

    private func drawBodies(_ ctx: GraphicsContext, _ positions: [BodyPosition], radius: Double,
                            point: (Double, Double) -> CGPoint, color: Color) {
        for p in positions {
            let pt = point(p.longitude.degrees, radius)
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4)),
                     with: .color(color.opacity(0.9)))
            let glyphPoint = point(p.longitude.degrees, radius - 15)
            ctx.draw(Text(p.body.glyph).font(.system(size: 14, weight: .medium)).foregroundStyle(color),
                     at: glyphPoint)
        }
    }

    private func label(_ ctx: GraphicsContext, _ s: String, _ at: CGPoint, _ color: Color) {
        ctx.draw(Text(s).font(.system(size: 10, weight: .bold)).foregroundStyle(color), at: at)
    }
}

/// A single-wheel rendering of a **composite chart** (no houses — composite
/// houses are unsettled; we show signs, planets, angles and aspects).
struct CompositeWheel: View {
    let composite: CompositeChart
    private let tint = AppScreen.astrology.tint

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let R = min(size.width, size.height) / 2 - 6
            let rZodiac = R * 0.84
            let rBody = R * 0.58
            let rHub = R * 0.32
            let asc = composite.ascendant.degrees

            func point(_ lonDeg: Double, _ r: Double) -> CGPoint {
                let phi = (180.0 + (lonDeg - asc)) * .pi / 180.0
                return CGPoint(x: c.x + r * cos(phi), y: c.y - r * sin(phi))
            }

            for r in [R, rZodiac, rHub] {
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(.white.opacity(0.16)), lineWidth: 1)
            }

            for sign in ZodiacSign.allCases {
                let start = sign.startLongitude.degrees
                ctx.stroke(Path { p in
                    p.move(to: point(start, rHub)); p.addLine(to: point(start, R))
                }, with: .color(.white.opacity(0.14)), lineWidth: 1)
                ctx.draw(Text(sign.glyph).font(.system(size: 14)).foregroundStyle(SynastryStyle.element(sign.element)),
                         at: point(start + 15, (R + rZodiac) / 2))
            }

            for a in composite.aspects {
                guard let pa = composite.position(of: a.bodyA), let pb = composite.position(of: a.bodyB) else { continue }
                ctx.stroke(Path { p in
                    p.move(to: point(pa.longitude.degrees, rHub))
                    p.addLine(to: point(pb.longitude.degrees, rHub))
                }, with: .color(SynastryStyle.aspect(a.kind).opacity(0.5)),
                   lineWidth: a.kind.isMajor ? 1.0 : 0.5)
            }

            for p in composite.positions {
                let pt = point(p.longitude.degrees, rBody)
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4)),
                         with: .color(.yellow.opacity(0.9)))
                ctx.draw(Text(p.body.glyph).font(.system(size: 14, weight: .medium)).foregroundStyle(.white),
                         at: point(p.longitude.degrees, rBody - 15))
            }

            ctx.draw(Text("AC").font(.system(size: 10, weight: .bold)).foregroundStyle(tint), at: point(asc, R))
            ctx.draw(Text("MC").font(.system(size: 10, weight: .bold)).foregroundStyle(tint),
                     at: point(composite.midheaven.degrees, R))
        }
        .accessibilityElement()
        .accessibilityLabel("Composite chart wheel")
    }
}

/// Shared colour helpers for the relationship wheels.
enum SynastryStyle {
    static func element(_ e: ZodiacSign.Element) -> Color {
        switch e {
        case .fire: Color(red: 1.0, green: 0.5, blue: 0.4)
        case .earth: Color(red: 0.5, green: 0.85, blue: 0.55)
        case .air: Color(red: 0.95, green: 0.85, blue: 0.5)
        case .water: Color(red: 0.5, green: 0.75, blue: 1.0)
        }
    }

    static func aspect(_ k: AspectKind) -> Color {
        switch k {
        case .trine, .sextile: .cyan
        case .square, .opposition: .red
        case .conjunction: .white
        default: .purple
        }
    }
}
