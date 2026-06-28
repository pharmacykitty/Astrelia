import SwiftUI
import simd
import CelestialCore
import Astrology

// SwiftUI also declares `Angle`; here we always mean the astronomy one.
private typealias Angle = CelestialCore.Angle

/// A rotating 3D celestial sphere of a chart — the local sky as a luminous globe:
/// the real star field, the horizon ring, celestial equator, the ecliptic ringed
/// with the zodiac, the planets, and the aspect chords across the interior.
/// Auto-rotates; drag to turn, tap to pause. Inspired by Astrolog's globe.
///
/// Everything is computed in the **local horizon frame** (z = zenith, x = north,
/// y = east): a body's ecliptic longitude → equatorial → horizontal → a unit
/// vector, then rotated (yaw about the vertical, pitch from the drag) and drawn
/// orthographically. Geometry is built once per chart and cached; only the cheap
/// per-frame projection runs in the render loop.
struct CelestialSphereView: View {
    let chart: NatalChart
    var title: String
    var subtitle: String?
    var stars: [Star] = []
    var constellations: [Constellation] = []

    @State private var geo: SphereGeometry?
    @State private var dragYaw = 0.0
    @State private var pitch = 18.0 * .pi / 180.0
    @GestureState private var live: (yaw: Double, pitch: Double) = (0, 0)
    @State private var paused = false

    private var rebuildKey: String {
        "\(chart.julianDay.value)|\(chart.location.latitude.degrees)|\(chart.location.longitude.degrees)|\(stars.count)|\(constellations.count)"
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color.black.ignoresSafeArea()
                if let geo {
                    TimelineView(.animation(paused: paused)) { tl in
                        let spin = paused ? 0 : tl.date.timeIntervalSinceReferenceDate * (2 * .pi / 60.0)
                        let yaw = spin + dragYaw + live.yaw
                        let p = clampPitch(pitch + live.pitch)
                        Canvas { ctx, sz in geo.draw(in: ctx, size: sz, yaw: yaw, pitch: p) }
                    }
                }
                footer
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .updating($live) { v, state, _ in
                        state = (v.translation.width * 0.01, -v.translation.height * 0.01)
                    }
                    .onEnded { v in
                        dragYaw += v.translation.width * 0.01
                        pitch = clampPitch(pitch - v.translation.height * 0.01)
                    }
            )
            .onTapGesture { paused.toggle() }
            .frame(width: size.width, height: size.height)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task(id: rebuildKey) { geo = SphereGeometry(chart: chart, stars: stars, constellations: constellations) }
    }

    private func clampPitch(_ p: Double) -> Double { max(-(.pi / 2 - 0.05), min(.pi / 2 - 0.05, p)) }

    private var footer: some View {
        VStack {
            Spacer()
            Text(subtitle ?? geo?.defaultSubtitle ?? "")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
                .padding(.bottom, 12)
        }
    }
}

/// Precomputed sphere geometry (horizon-frame base vectors). Built once per chart;
/// rotation/projection happen per frame in `draw`.
private struct SphereGeometry {
    struct StarDot { let v: SIMD3<Double>; let color: Color; let size: Double; let alpha: Double; let spike: Double }
    struct Planet { let v: SIMD3<Double>; let body: AstroBody; let retro: Bool }

    let horizon: [SIMD3<Double>]
    let equator: [SIMD3<Double>]
    let ecliptic: [SIMD3<Double>]
    let meridian: [SIMD3<Double>]
    let cuspTicks: [SIMD3<Double>]
    let zodiac: [(v: SIMD3<Double>, glyph: String)]
    let constellationSegments: [(a: SIMD3<Double>, b: SIMD3<Double>)]
    let starField: [StarDot]
    let planets: [Planet]
    let aspects: [(a: SIMD3<Double>, b: SIMD3<Double>, color: Color)]
    let cardinals: [(v: SIMD3<Double>, label: String)]
    let zenith: SIMD3<Double>
    let ascendant: SIMD3<Double>
    let midheaven: SIMD3<Double>
    let defaultSubtitle: String

    init(chart: NatalChart, stars: [Star], constellations: [Constellation] = []) {
        let ob = chart.angles.obliquity
        let ramc = chart.angles.ramc
        let loc = chart.location

        func vec(eclipticLon lon: Angle, lat: Angle = .zero) -> SIMD3<Double> {
            let eq = CoordinateTransform.equatorial(
                fromEcliptic: EclipticCoordinates(longitude: lon, latitude: lat), obliquity: ob)
            let h = CoordinateTransform.horizontal(eq, at: loc, localSiderealTime: ramc)
            return SphereGeometry.unit(altitude: h.altitude, azimuth: h.azimuth)
        }
        func vecEquatorial(_ eq: EquatorialCoordinates) -> SIMD3<Double> {
            let h = CoordinateTransform.horizontal(eq, at: loc, localSiderealTime: ramc)
            return SphereGeometry.unit(altitude: h.altitude, azimuth: h.azimuth)
        }

        let step = 2.0
        horizon = stride(from: 0.0, through: 360.0, by: step).map {
            SphereGeometry.unit(altitude: .zero, azimuth: .degrees($0))
        }
        equator = stride(from: 0.0, through: 360.0, by: step).map {
            vecEquatorial(EquatorialCoordinates(rightAscension: .degrees($0), declination: .zero))
        }
        ecliptic = stride(from: 0.0, through: 360.0, by: step).map { vec(eclipticLon: .degrees($0)) }
        meridian = stride(from: 0.0, through: 360.0, by: step).map {
            SIMD3(cos(Angle.degrees($0).radians), 0, sin(Angle.degrees($0).radians))
        }

        zodiac = ZodiacSign.allCases.map {
            (vec(eclipticLon: .degrees(Double($0.rawValue) * 30 + 15)), $0.glyph)
        }
        cuspTicks = (1...12).map { vec(eclipticLon: chart.houses.cusp($0)) }

        // Real star field: brightest first, capped for a clean, fast render.
        let bright = stars.sorted { $0.apparentMagnitude < $1.apparentMagnitude }.prefix(900)
        starField = bright.map { s in
            let m = s.apparentMagnitude
            return StarDot(v: vecEquatorial(s.equatorial),
                           color: SphereGeometry.starColor(s.colorIndex),
                           size: max(0.5, 2.3 - 0.34 * m),
                           alpha: max(0.18, min(1.0, 1.15 - 0.16 * m)),
                           // Diffraction-spike sparkle for the few brightest stars.
                           spike: m < 1.6 ? (8.0 - 3.0 * m) : 0)
        }

        // Constellation stick-figures (RA/Dec polylines) → horizon-frame segments.
        var segs: [(a: SIMD3<Double>, b: SIMD3<Double>)] = []
        for c in constellations {
            for line in c.polylines where line.count > 1 {
                let pts = line.map { vecEquatorial(EquatorialCoordinates(
                    rightAscension: .degrees($0.x), declination: .degrees($0.y))) }
                for i in 0..<(pts.count - 1) { segs.append((pts[i], pts[i + 1])) }
            }
        }
        constellationSegments = segs

        planets = chart.positions.map {
            Planet(v: vec(eclipticLon: $0.longitude), body: $0.body, retro: $0.isRetrograde)
        }

        let posByBody = Dictionary(uniqueKeysWithValues: chart.positions.map { ($0.body, $0.longitude) })
        aspects = chart.aspects.compactMap { asp in
            guard let la = posByBody[asp.bodyA], let lb = posByBody[asp.bodyB] else { return nil }
            return (vec(eclipticLon: la), vec(eclipticLon: lb), SphereGeometry.aspectColor(asp.kind))
        }

        cardinals = [(0.0, "N"), (90, "E"), (180, "S"), (270, "W")].map {
            (SphereGeometry.unit(altitude: .zero, azimuth: .degrees($0.0)), $0.1)
        }

        zenith = SIMD3(0, 0, 1)
        ascendant = vec(eclipticLon: chart.angles.ascendant)
        midheaven = vec(eclipticLon: chart.angles.midheaven)

        let date = Date(timeIntervalSince1970: (chart.julianDay.value - 2440587.5) * 86400)
        let df = DateFormatter()
        df.dateFormat = "EEE d MMM yyyy HH:mm 'UTC'"
        df.timeZone = .gmt
        defaultSubtitle = String(format: "%@   %.2f°, %.2f°",
                                 df.string(from: date), loc.latitude.degrees, loc.longitude.degrees)
    }

    /// Horizon-frame unit vector: x = north, y = east, z = zenith.
    static func unit(altitude alt: Angle, azimuth az: Angle) -> SIMD3<Double> {
        SIMD3(cos(alt.radians) * cos(az.radians),
              cos(alt.radians) * sin(az.radians),
              sin(alt.radians))
    }

    static func aspectColor(_ k: AspectKind) -> Color {
        switch k {
        case .trine, .sextile: return Color(red: 0.4, green: 0.85, blue: 1.0)
        case .square, .opposition: return Color(red: 1.0, green: 0.4, blue: 0.45)
        case .conjunction: return .white
        default: return Color(red: 0.75, green: 0.6, blue: 1.0)
        }
    }

    static func starColor(_ bv: Double?) -> Color {
        guard let bv else { return .white }
        switch bv {
        case ..<0.0: return Color(red: 0.74, green: 0.82, blue: 1.0)
        case 0.0..<0.3: return Color(red: 0.92, green: 0.95, blue: 1.0)
        case 0.3..<0.6: return Color(red: 1.0, green: 0.98, blue: 0.92)
        case 0.6..<1.0: return Color(red: 1.0, green: 0.92, blue: 0.76)
        default: return Color(red: 1.0, green: 0.82, blue: 0.66)
        }
    }

    static func planetColor(_ b: AstroBody) -> Color {
        switch b {
        case .sun: return Color(red: 1.0, green: 0.85, blue: 0.4)
        case .moon: return Color(red: 0.86, green: 0.89, blue: 0.96)
        case .mercury: return Color(red: 0.82, green: 0.78, blue: 0.66)
        case .venus: return Color(red: 0.96, green: 0.92, blue: 0.72)
        case .mars: return Color(red: 0.97, green: 0.47, blue: 0.37)
        case .jupiter: return Color(red: 0.96, green: 0.78, blue: 0.55)
        case .saturn: return Color(red: 0.9, green: 0.85, blue: 0.6)
        case .uranus: return Color(red: 0.62, green: 0.92, blue: 0.95)
        case .neptune: return Color(red: 0.5, green: 0.66, blue: 1.0)
        case .pluto: return Color(red: 0.82, green: 0.58, blue: 0.5)
        case .northNode, .southNode: return Color(red: 0.72, green: 0.72, blue: 0.8)
        }
    }

    // MARK: Rotation & projection

    private func project(_ v: SIMD3<Double>, yaw: Double, pitch: Double,
                         center: CGPoint, radius: Double) -> (CGPoint, Double) {
        let cyaw = cos(yaw), syaw = sin(yaw)
        let x1 = v.x * cyaw - v.y * syaw
        let y1 = v.x * syaw + v.y * cyaw
        let z1 = v.z
        let cp = cos(pitch), sp = sin(pitch)
        let y2 = y1 * cp - z1 * sp     // depth toward viewer
        let z2 = y1 * sp + z1 * cp     // screen vertical
        return (CGPoint(x: center.x + radius * x1, y: center.y - radius * z2), y2)
    }

    func draw(in ctx: GraphicsContext, size: CGSize, yaw: Double, pitch: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = Double(min(size.width, size.height)) / 2 - 22
        func p(_ v: SIMD3<Double>) -> (CGPoint, Double) {
            project(v, yaw: yaw, pitch: pitch, center: center, radius: radius)
        }
        let limb = CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)

        // Globe volume + atmosphere rim.
        ctx.fill(Path(ellipseIn: limb),
                 with: .radialGradient(
                    Gradient(colors: [Color(red: 0.03, green: 0.05, blue: 0.12),
                                      Color(red: 0.01, green: 0.01, blue: 0.04)]),
                    center: center, startRadius: 0, endRadius: radius))
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 7))
            layer.stroke(Path(ellipseIn: limb),
                         with: .color(Color(red: 0.4, green: 0.55, blue: 1.0).opacity(0.4)), lineWidth: 2.5)
        }
        ctx.stroke(Path(ellipseIn: limb), with: .color(.white.opacity(0.10)), lineWidth: 1)

        // Faint constellation stick-figures.
        for seg in constellationSegments {
            let (pa, da) = p(seg.a); let (pb, db) = p(seg.b)
            let a = (da + db) / 2 >= 0 ? 0.14 : 0.05
            ctx.stroke(Path { $0.move(to: pa); $0.addLine(to: pb) },
                       with: .color(Color(red: 0.6, green: 0.7, blue: 1.0).opacity(a)), lineWidth: 0.5)
        }

        // Star field, with diffraction sparkle on the brightest.
        for s in starField {
            let (pt, depth) = p(s.v)
            let a = s.alpha * (depth >= 0 ? 1.0 : 0.32)
            let r = s.size * (depth >= 0 ? 1.0 : 0.8)
            if s.spike > 0 {
                let L = s.spike * (depth >= 0 ? 1.0 : 0.6)
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 1.2))
                    var path = Path()
                    path.move(to: CGPoint(x: pt.x - L, y: pt.y)); path.addLine(to: CGPoint(x: pt.x + L, y: pt.y))
                    path.move(to: CGPoint(x: pt.x, y: pt.y - L)); path.addLine(to: CGPoint(x: pt.x, y: pt.y + L))
                    layer.stroke(path, with: .color(s.color.opacity(a * 0.7)), lineWidth: 0.6)
                }
            }
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: 2 * r, height: 2 * r)),
                     with: .color(s.color.opacity(a)))
        }

        // Great circles.
        circle(equator, color: .init(red: 0.45, green: 0.6, blue: 1.0), base: 0.45, ctx: ctx, p: p)
        circle(meridian, color: .gray, base: 0.28, ctx: ctx, p: p, dashed: true)
        circle(ecliptic, color: .init(red: 0.5, green: 1.0, blue: 0.6), base: 0.85, width: 1.5, glow: true, ctx: ctx, p: p)
        circle(horizon, color: .white, base: 0.7, width: 1.2, ctx: ctx, p: p)

        // Graduated horizon ticks every 10°, longer at the cardinals.
        for az in stride(from: 0.0, to: 360.0, by: 10.0) {
            let major = az.truncatingRemainder(dividingBy: 90) == 0
            let (a0, d0) = p(SphereGeometry.unit(altitude: .degrees(major ? -3 : -1.6), azimuth: .degrees(az)))
            let (a1, _) = p(SphereGeometry.unit(altitude: .degrees(major ? 3 : 1.6), azimuth: .degrees(az)))
            ctx.stroke(Path { $0.move(to: a0); $0.addLine(to: a1) },
                       with: .color(.white.opacity(d0 >= 0 ? 0.5 : 0.16)), lineWidth: major ? 1.2 : 0.6)
        }

        // House-cusp ticks on the ecliptic.
        for v in cuspTicks {
            let (pt, depth) = p(v)
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 1.3, y: pt.y - 1.3, width: 2.6, height: 2.6)),
                     with: .color(.white.opacity(depth >= 0 ? 0.5 : 0.18)))
        }

        // Zodiac glyphs.
        for z in zodiac {
            let (pt, depth) = p(z.v)
            let a = depth >= 0 ? 0.9 : 0.25
            ctx.draw(Text(z.glyph).font(.system(size: 13))
                        .foregroundStyle(Color(red: 0.85, green: 0.6, blue: 1.0).opacity(a)), at: pt)
        }

        // Aspect chords.
        for asp in aspects {
            let (pa, da) = p(asp.a); let (pb, db) = p(asp.b)
            let a = (da + db) / 2 >= 0 ? 0.55 : 0.18
            ctx.stroke(Path { $0.move(to: pa); $0.addLine(to: pb) },
                       with: .color(asp.color.opacity(a)), lineWidth: 1)
        }

        // Planets, drawn back-to-front, with a soft glow.
        for entry in planets.map({ ($0, p($0.v)) }).sorted(by: { $0.1.1 < $1.1.1 }) {
            let (planet, (pt, depth)) = entry
            let color = SphereGeometry.planetColor(planet.body)
            let a = depth >= 0 ? 1.0 : 0.4
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 4))
                layer.fill(Path(ellipseIn: CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12)),
                           with: .color(color.opacity(0.5 * a)))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2.6, y: pt.y - 2.6, width: 5.2, height: 5.2)),
                     with: .color(color.opacity(a)))
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 1, y: pt.y - 1, width: 2, height: 2)),
                     with: .color(.white.opacity(a)))
            var label = Text(planet.body.glyph).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(a))
            if planet.retro {
                label = label + Text(" ℞").font(.system(size: 8)).foregroundStyle(.orange.opacity(a))
            }
            ctx.draw(label, at: CGPoint(x: pt.x, y: pt.y - 14))
        }

        // Cardinal directions + key points.
        for c in cardinals { label(c.label, c.v, .white.opacity(0.55), size: 9, ctx: ctx, p: p) }
        label("Z", zenith, .yellow, ctx: ctx, p: p)
        label("AC", ascendant, AppScreen.astrology.tint, ctx: ctx, p: p)
        label("MC", midheaven, AppScreen.astrology.tint, ctx: ctx, p: p)
    }

    private func circle(_ pts: [SIMD3<Double>], color: Color, base: Double, width: Double = 1,
                        glow: Bool = false, ctx: GraphicsContext,
                        p: (SIMD3<Double>) -> (CGPoint, Double), dashed: Bool = false) {
        var front = Path(), back = Path()
        var inFront = false, inBack = false
        for v in pts {
            let (pt, depth) = p(v)
            if depth >= 0 {
                if inFront { front.addLine(to: pt) } else { front.move(to: pt); inFront = true }
                inBack = false
            } else {
                if inBack { back.addLine(to: pt) } else { back.move(to: pt); inBack = true }
                inFront = false
            }
        }
        let style = StrokeStyle(lineWidth: width, dash: dashed ? [2, 4] : [])
        ctx.stroke(back, with: .color(color.opacity(base * 0.28)), style: style)
        if glow {
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 3))
                layer.stroke(front, with: .color(color.opacity(base * 0.6)),
                             style: StrokeStyle(lineWidth: width + 2))
            }
        }
        ctx.stroke(front, with: .color(color.opacity(base)), style: style)
    }

    private func label(_ s: String, _ v: SIMD3<Double>, _ color: Color, size: Double = 10,
                       ctx: GraphicsContext, p: (SIMD3<Double>) -> (CGPoint, Double)) {
        let (pt, depth) = p(v)
        let a = depth >= 0 ? 1.0 : 0.3
        ctx.draw(Text(s).font(.system(size: size, weight: .bold)).foregroundStyle(color.opacity(a)), at: pt)
    }
}
