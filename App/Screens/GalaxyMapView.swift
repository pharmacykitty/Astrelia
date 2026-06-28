import SwiftUI
import UIKit
import simd
import CelestialCore

/// A 3D fly-through of the real local star field (HYG positions, in parsecs, with
/// the Sun at the origin). Drag to orbit, pinch to zoom, tap a star to inspect it.
/// This is the foundation of the flagship Galaxy Map; the stylized Milky Way
/// backdrop and exoplanets build on top of it.
/// An optional object to centre on when the Galaxy Map opens (e.g. from the Catalog).
enum GalaxyMapFocus {
    case landmark(Landmark)
    case star(Int)
}

struct GalaxyMapView: View {
    let store: StarCatalogStore
    let exo: ExoplanetStore
    var focus: GalaxyMapFocus? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var focusApplied = false
    @State private var shownSystem: PlanetarySystem?
    @State private var showMilkyWay = true          // toggle the stylized backdrop off to see only real objects
    @State private var hostsOnly = false            // show only stars with known planets (+ Sun & landmarks)
    @State private var showOptions = false          // the drop-down view-options panel
    @State private var showCatalog = false
    @State private var stars: [GalaxyStar] = []
    @State private var backdrop: [BackdropPoint] = []   // stylized Milky Way (art, not catalogued)
    @State private var backdropDust: [BackdropPoint] = []   // dark dust lanes, carved over the glow
    @State private var flightTask: Task<Void, Never>?

    // Orbit camera (parsecs).
    @State private var yaw: Float = 0.6
    @State private var pitch: Float = 0.35
    @State private var distance: Float = 220
    @State private var target = SIMD3<Float>(0, 0, 0)

    @State private var dragPrevious: CGSize = .zero
    @State private var zoomAnchor: Float = 220

    // Free-fly camera: a free eye position + look direction. One finger drags to
    // steer; a two-finger vertical drag sets a *persistent* throttle (-1…1) so you
    // can lift off and cruise hands-free while steering. `throttling` is true only
    // while the two-finger gesture is active, so steering is suppressed mid-throttle.
    @State private var flyMode = false
    @State private var eye = SIMD3<Float>(0, 0, 0)
    @State private var throttle: Float = 0
    @State private var throttling = false
    @State private var flyTask: Task<Void, Never>?
    private let flySpeed: Float = 1540   // parsecs/second at full throttle

    @State private var selection: MapSelection?

    /// What the user has tapped — the Sun, a real star, or a curated landmark.
    private enum MapSelection {
        case sun
        case star(GalaxyStar)
        case landmark(Landmark)

        var position: SIMD3<Float> {
            switch self {
            case .sun: .zero
            case .star(let s): s.position
            case .landmark(let l): l.positionParsecs
            }
        }
    }

    private let fieldOfView: Float = 0.9   // radians (~51°)

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let viewProjection = makeViewProjection(aspect: Float(size.width / max(size.height, 1)))
            // Read here (not just inside the Canvas closure) so the view re-renders
            // when the exoplanet catalog finishes loading.
            let hostHIPs = exo.hostHIPs

            ZStack {
                LinearGradient(colors: [Color(red: 0.01, green: 0.01, blue: 0.05), .black],
                               startPoint: .top, endPoint: .bottom)

                // Gestures live on the canvas layer (below the overlay) so taps on
                // overlay buttons interact with the button, not the stars behind it.
                Canvas { context, _ in
                    draw(in: context, size: size, viewProjection: viewProjection, hostHIPs: hostHIPs)
                }
                .contentShape(Rectangle())
                .gesture(dragGesture)
                .simultaneousGesture(zoomGesture)
                .simultaneousGesture(tapGesture(size: size, viewProjection: viewProjection, hostHIPs: hostHIPs))

                overlay(size: size, viewProjection: viewProjection, safe: .deviceSafeArea)
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: store.catalog?.count ?? 0) {
            buildStars(); buildBackdrop(); applyInitialFocusIfNeeded()
        }
        .onDisappear { flightTask?.cancel(); flyTask?.cancel() }
        .fullScreenCover(item: $shownSystem) { SystemView(system: $0) }
        .fullScreenCover(isPresented: $showCatalog) {
            NavigationStack {
                CatalogView(store: store, exo: exo)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            CircleIconButton(label: "Close", systemImage: "xmark") { showCatalog = false }
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: Rendering

    private func draw(in context: GraphicsContext, size: CGSize, viewProjection: simd_float4x4, hostHIPs: Set<Int>) {
        let focal = Double(1 / tan(fieldOfView / 2))
        let halfH = Double(size.height) * 0.5
        let maxDim = Double(max(size.width, size.height))

        // Broad warm glow for the galactic core/bulge — a soft luminous centre.
        // The disc/arm haze is no longer a flat circle: it comes from the bloom
        // pass over the real point field below, so it follows the true spiral/bar
        // shape and viewing angle instead of reading as a smudge.
        if showMilkyWay, let (cp, cdepth) = project(Galactic.centerPosition, viewProjection, size), cdepth > 0 {
            let pxPerPc = halfH * focal / Double(cdepth)
            let coreR = CGFloat(min(maxDim * 0.9, 3000 * pxPerPc))
            if coreR > 4 {
                context.drawLayer { layer in
                    layer.blendMode = .plusLighter
                    layer.fill(Path(ellipseIn: CGRect(x: cp.x - coreR, y: cp.y - coreR, width: coreR * 2, height: coreR * 2)),
                               with: .radialGradient(Gradient(colors: [Color(red: 1.0, green: 0.92, blue: 0.74).opacity(0.42),
                                                                        Color(red: 1.0, green: 0.85, blue: 0.6).opacity(0.12), .clear]),
                                                     center: cp, startRadius: 0, endRadius: coreR))
                }
            }
        }

        // Stylized Milky Way point field, drawn in two additive passes for a
        // photographic look: a heavy-blur *bloom* that fuses the points into smooth
        // luminous structure following the real arms/bar, then a crisp pass for
        // defined cores. Points are batched by colour + opacity level (a few dozen
        // fills, built once and reused by both passes); off-screen/sub-pixel culled.
        if showMilkyWay {
            var paths = Array(repeating: Array(repeating: Path(), count: backdropOpacityLevels.count),
                              count: backdropPalette.count)
            for point in backdrop {
                guard let (p, depth) = project(point.position, viewProjection, size) else { continue }
                if p.x < -6 || p.x > size.width + 6 || p.y < -6 || p.y > size.height + 6 { continue }
                let r = point.size * CGFloat(min(3.4, max(0.6, Double(800 / depth))))
                if r < 0.4 { continue }
                let lvl = min(backdropOpacityLevels.count - 1, Int(point.baseOpacity * Double(backdropOpacityLevels.count)))
                paths[point.colorBucket][lvl].addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
            context.drawLayer { layer in            // bloom — soft structure-following haze
                layer.addFilter(.blur(radius: 8))
                layer.blendMode = .plusLighter
                for c in backdropPalette.indices {
                    for l in backdropOpacityLevels.indices {
                        layer.fill(paths[c][l], with: .color(backdropPalette[c].opacity(backdropOpacityLevels[l] * 0.55)))
                    }
                }
            }
            context.drawLayer { layer in            // crisp cores
                layer.addFilter(.blur(radius: 1.1))
                layer.blendMode = .plusLighter
                for c in backdropPalette.indices {
                    for l in backdropOpacityLevels.indices {
                        layer.fill(paths[c][l], with: .color(backdropPalette[c].opacity(backdropOpacityLevels[l])))
                    }
                }
            }
        }

        // Real stars: one path per colour bucket → 6 fills total, with off-screen +
        // sub-pixel culling and an overall cap for level-of-detail.
        var starPaths = Array(repeating: Path(), count: starPalette.count)
        var glowPath = Path()
        var hostBadges = Path()         // rings around stars with known planets
        var drawn = 0
        for star in stars {
            let isHost = star.hip.map { hostHIPs.contains($0) } ?? false
            if hostsOnly && !isHost { continue }
            guard let (p, depth) = project(star.position, viewProjection, size) else { continue }
            if p.x < -3 || p.x > size.width + 3 || p.y < -3 || p.y > size.height + 3 { continue }
            let r = star.baseSize * CGFloat(min(3.0, max(0.4, 150 / depth)))
            if r < 0.5 && !hostsOnly { continue }
            if star.magnitude < 1.5 {
                let g = r * 3
                glowPath.addEllipse(in: CGRect(x: p.x - g, y: p.y - g, width: g * 2, height: g * 2))
            }
            // In hosts-only mode give every host a floor size so distant ones stay visible.
            let rr = hostsOnly ? max(r, 1.6) : r
            starPaths[star.colorBucket].addEllipse(in: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2))
            if isHost {
                let br = max(rr + 3, 5)
                hostBadges.addEllipse(in: CGRect(x: p.x - br, y: p.y - br, width: br * 2, height: br * 2))
            }
            drawn += 1
            if drawn >= 14000 { break }
        }
        context.fill(glowPath, with: .color(.white.opacity(0.12)))
        for i in starPalette.indices {
            context.fill(starPaths[i], with: .color(starPalette[i].opacity(0.95)))
        }
        context.stroke(hostBadges, with: .color(Color(red: 0.4, green: 0.95, blue: 0.9).opacity(0.8)), lineWidth: 1)

        // The Sun at the origin.
        if let (sunPoint, _) = project(.zero, viewProjection, size) {
            context.fill(Path(ellipseIn: CGRect(x: sunPoint.x - 7, y: sunPoint.y - 7, width: 14, height: 14)),
                         with: .color(.orange.opacity(0.25)))
            context.fill(Path(ellipseIn: CGRect(x: sunPoint.x - 3, y: sunPoint.y - 3, width: 6, height: 6)),
                         with: .color(.orange))
            context.draw(Text("Sol").font(.system(size: 10, weight: .semibold)).foregroundStyle(.orange),
                         at: CGPoint(x: sunPoint.x, y: sunPoint.y + 14))
        }

        // Deep-sky landmarks — rendered at true physical scale: distant ones are
        // small markers, but they grow into glowing clouds / star clusters as you
        // approach, sized by their real radius. Plus a de-cluttered label.
        var labelRects: [CGRect] = []
        for landmark in Landmarks.all {
            guard let (p, depth) = project(landmark.positionParsecs, viewProjection, size), depth > 0 else { continue }
            let screenRadius = landmark.radiusParsecs * (Double(size.height) * 0.5) * focal / Double(depth)
            let r = CGFloat(max(2.0, min(screenRadius, Double(max(size.width, size.height)) * 1.5)))
            if p.x < -r - 30 || p.x > size.width + r + 30 || p.y < -r - 30 || p.y > size.height + r + 30 { continue }

            if r >= 4 {
                drawLandmark(context, landmark, at: p, radius: r, viewProjection: viewProjection, size: size)
            } else {
                let color = landmark.type.color
                context.fill(Path(ellipseIn: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16)), with: .color(color.opacity(0.13)))
                context.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(color.opacity(0.45)))
                context.fill(Path(ellipseIn: CGRect(x: p.x - 1.6, y: p.y - 1.6, width: 3.2, height: 3.2)), with: .color(.white.opacity(0.95)))
            }

            let labelY = p.y + CGFloat(min(Double(r) + 8, 70))
            let text = Text(landmark.name).font(.system(size: 9, weight: .medium)).foregroundStyle(landmark.type.color.opacity(0.95))
            let resolved = context.resolve(text)
            let m = resolved.measure(in: CGSize(width: 160, height: 40))
            let rect = CGRect(x: p.x - m.width / 2, y: labelY - m.height / 2, width: m.width, height: m.height)
            if rect.minX > 2, rect.maxX < size.width - 2, rect.minY > 2, rect.maxY < size.height - 2,
               !labelRects.contains(where: { $0.intersects(rect) }) {
                labelRects.append(rect.insetBy(dx: -3, dy: -3))
                context.draw(resolved, at: CGPoint(x: p.x, y: labelY))
            }
        }

        // Selection ring + label.
        if let selection, let (point, _) = project(selection.position, viewProjection, size) {
            context.stroke(Path(ellipseIn: CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24)),
                           with: .color(.white), lineWidth: 1.5)
        }
    }

    /// Draws a landmark at true scale: a glowing nebula cloud, star cluster, galaxy
    /// haze, or black-hole glow, sized to its projected physical radius.
    private func drawLandmark(_ context: GraphicsContext, _ landmark: Landmark, at p: CGPoint, radius r: CGFloat,
                              viewProjection: simd_float4x4, size: CGSize) {
        let color = landmark.type.color
        func rect(_ c: CGPoint, _ rad: CGFloat) -> CGRect { CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2) }
        // Stable per-object seed (String.hashValue is randomised per launch, so don't use it).
        var rng = SeededGenerator(seed: landmark.id.unicodeScalars.reduce(UInt64(1469598103)) { $0 &* 31 &+ UInt64($1.value) })
        func rnd(_ a: Double, _ b: Double) -> Double { Double.random(in: a...b, using: &rng) }
        func gauss() -> Double {
            let u1 = Double.random(in: 1e-6...1, using: &rng), u2 = Double.random(in: 0...1, using: &rng)
            return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        }

        switch landmark.type {
        case .emissionNebula, .supernovaRemnant, .planetaryNebula:
            drawNebula(context, landmark, at: p, radius: r, viewProjection: viewProjection, size: size)

        case .openCluster, .globularCluster:
            let globular = landmark.type == .globularCluster
            // Member stars live in 3D, scattered in a sphere around the cluster's real
            // position, then projected individually — so the cluster rotates and
            // parallaxes with the camera instead of being a flat decal on the screen.
            let center = landmark.positionParsecs
            let physR = Float(landmark.radiusParsecs)
            let n = globular ? 220 : 60
            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                if globular {
                    layer.fill(Path(ellipseIn: rect(p, r * 0.6)),
                               with: .radialGradient(Gradient(colors: [color.opacity(0.28), .clear]),
                                                     center: p, startRadius: 0, endRadius: r * 0.6))
                }
                for _ in 0..<n {
                    // Random direction on the unit sphere.
                    let z = rnd(-1, 1)
                    let t = rnd(0, 2 * .pi)
                    let rxy = (1 - z * z).squareRoot()
                    let dir = SIMD3<Float>(Float(cos(t) * rxy), Float(sin(t) * rxy), Float(z))
                    // Globulars concentrate toward the core; open clusters fill the sphere.
                    let frac = globular ? min(1, abs(gauss()) * 0.42) : pow(rnd(0, 1), 1.0 / 3.0)
                    let world = center + dir * (physR * Float(frac))
                    guard let (sp, depth) = project(world, viewProjection, size), depth > 0 else { continue }
                    if sp.x < -4 || sp.x > size.width + 4 || sp.y < -4 || sp.y > size.height + 4 { continue }
                    let dr = CGFloat(max(0.6, min(3.0, Double(r) * rnd(0.025, 0.055))))
                    layer.fill(Path(ellipseIn: rect(sp, dr)), with: .color(.white.opacity(rnd(0.6, 0.95))))
                }
            }

        case .galaxy:
            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                let rx = r, ry = r * 0.6
                layer.fill(Path(ellipseIn: CGRect(x: p.x - rx, y: p.y - ry, width: rx * 2, height: ry * 2)),
                           with: .radialGradient(Gradient(colors: [color.opacity(0.32), .clear]),
                                                 center: p, startRadius: 0, endRadius: r))
                for _ in 0..<90 {
                    let ang = rnd(0, 2 * .pi), rad = rnd(0, 1)
                    let sp = CGPoint(x: p.x + CGFloat(cos(ang) * rad * Double(rx)), y: p.y + CGFloat(sin(ang) * rad * Double(ry)))
                    layer.fill(Path(ellipseIn: rect(sp, CGFloat(rnd(0.5, 1.4)))), with: .color(.white.opacity(0.7)))
                }
            }

        case .blackHole:
            let radius = max(6, min(r, 46))
            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                layer.fill(Path(ellipseIn: rect(p, radius)),
                           with: .radialGradient(Gradient(colors: [color.opacity(0.55), .clear]),
                                                 center: p, startRadius: radius * 0.18, endRadius: radius))
                layer.fill(Path(ellipseIn: rect(p, max(2, radius * 0.14))), with: .color(.white))
            }
        }
    }

    /// Renders a nebula as a genuine volumetric cloud rather than a flat decal: gas
    /// "puffs" are distributed in real 3D space around the object's position and
    /// projected individually, so the cloud has depth, internal structure, and
    /// parallaxes / rotates with the camera — you can even fly into it. Same trick the
    /// clusters use for their member stars, applied to soft additive gas sprites.
    private func drawNebula(_ context: GraphicsContext, _ landmark: Landmark, at p: CGPoint,
                            radius r: CGFloat, viewProjection: simd_float4x4, size: CGSize) {
        let focal = Double(1 / tan(fieldOfView / 2))
        let halfH = Double(size.height) * 0.5
        let cap = CGFloat(max(size.width, size.height) * 1.5)

        // Stable per-object seed (String.hashValue is randomised per launch).
        var rng = SeededGenerator(seed: landmark.id.unicodeScalars.reduce(UInt64(1469598103)) { $0 &* 31 &+ UInt64($1.value) })
        func rnd(_ a: Double, _ b: Double) -> Double { Double.random(in: a...b, using: &rng) }
        func gauss() -> Double {
            let u1 = Double.random(in: 1e-6...1, using: &rng), u2 = Double.random(in: 0...1, using: &rng)
            return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        }
        func gauss3() -> SIMD3<Float> { SIMD3(Float(gauss()), Float(gauss()), Float(gauss())) }
        func unitDir() -> SIMD3<Float> {
            let z = rnd(-1, 1), t = rnd(0, 2 * .pi), rxy = (1 - z * z).squareRoot()
            return SIMD3(Float(cos(t) * rxy), Float(sin(t) * rxy), Float(z))
        }

        let center = landmark.positionParsecs
        let physR = Float(landmark.radiusParsecs)
        let color = landmark.type.color
        let teal = Color(red: 0.35, green: 0.7, blue: 0.95)   // OIII-ish cool tint
        let pink = Color(red: 1.0, green: 0.55, blue: 0.72)   // H-alpha warm knots

        // A randomly oriented anisotropy frame so clouds aren't axis-aligned blobs.
        let a = simd_normalize(gauss3() + SIMD3(0.0001, 0, 0))
        let b = simd_normalize(gauss3() - a * simd_dot(a, gauss3()))
        let (ex, ey, ez) = (a, b, simd_cross(a, b))
        let aniso = SIMD3<Float>(1.0, Float(rnd(0.55, 0.95)), Float(rnd(0.6, 0.95)))
        func shape(_ v: SIMD3<Float>) -> SIMD3<Float> {
            ex * (v.x * aniso.x) + ey * (v.y * aniso.y) + ez * (v.z * aniso.z)
        }

        // (worldPosition, physicalRadius in pc, colour, baseOpacity)
        var puffs: [(pos: SIMD3<Float>, rad: Float, color: Color, op: Double)] = []
        var embeddedStars: [SIMD3<Float>] = []

        switch landmark.type {
        case .planetaryNebula:
            // A thin glowing shell (the ejected envelope) with brighter bipolar lobes
            // along a random axis, around a hot white central star.
            let axis = simd_normalize(shape(unitDir()))
            let shellR = physR * 0.62
            for _ in 0..<70 {
                let d = shape(unitDir())
                let pos = center + d * shellR * Float(rnd(0.9, 1.08))
                let align = abs(simd_dot(simd_normalize(d), axis))
                puffs.append((pos, physR * Float(rnd(0.1, 0.2)), align > 0.6 ? color : teal, 0.22 + Double(align) * 0.3))
            }
            for s in [-1.0, 1.0] {
                let lobe = center + axis * (shellR * Float(s) * 0.8)
                for _ in 0..<14 {
                    puffs.append((lobe + shape(gauss3()) * shellR * 0.35, physR * Float(rnd(0.12, 0.24)), teal, 0.2))
                }
            }
            embeddedStars.append(center)

        case .supernovaRemnant:
            // A ragged filamentary shell: puffs over a sphere surface with radial
            // jitter, two-tone (H-alpha + the characteristic violet/teal), faint inside.
            let shellR = physR * 0.85
            let n = Int(min(170, max(80, Double(r))))
            for _ in 0..<n {
                let pos = center + shape(unitDir()) * shellR * Float(rnd(0.82, 1.06))
                puffs.append((pos, physR * Float(rnd(0.05, 0.12)), rnd(0, 1) < 0.5 ? color : pink, rnd(0.3, 0.52)))
            }
            for _ in 0..<24 {
                puffs.append((center + shape(gauss3()) * physR * 0.45, physR * Float(rnd(0.25, 0.5)), color, 0.06))
            }

        default:   // emissionNebula — a billowy, clumpy star-forming cloud
            let lobeCount = 7
            var lobes: [(SIMD3<Float>, Float)] = []
            for _ in 0..<lobeCount { lobes.append((shape(gauss3()) * (physR * 0.45), Float(rnd(0.4, 0.85)))) }
            let n = Int(min(150, max(60, Double(r) / 1.5)))
            for _ in 0..<n {
                let (lc, ls) = lobes[Int(rnd(0, Double(lobeCount) - 1e-3))]
                let pos = center + lc + shape(gauss3()) * (physR * ls * 0.5)
                let outer = Double(simd_length(lc) / max(physR, 0.001))
                let col = rnd(0, 1) < (0.22 + outer * 0.45) ? teal : (rnd(0, 1) < 0.85 ? color : pink)
                puffs.append((pos, physR * Float(rnd(0.18, 0.42)) * ls, col, rnd(0.07, 0.17)))
            }
            for _ in 0..<Int(min(18, max(6, Double(r) / 8))) {   // bright HII knots
                puffs.append((center + shape(gauss3()) * (physR * 0.4), physR * Float(rnd(0.05, 0.12)), pink, rnd(0.42, 0.62)))
            }
            for _ in 0..<8 { embeddedStars.append(center + shape(gauss3()) * (physR * 0.5)) }
        }

        // Project + cull, then depth-sort far → near so nearer gas layers over far gas.
        struct Sprite { let p: CGPoint; let r: CGFloat; let color: Color; let op: Double; let depth: Float }
        var sprites: [Sprite] = []
        sprites.reserveCapacity(puffs.count)
        for puff in puffs {
            guard let (sp, depth) = project(puff.pos, viewProjection, size), depth > 0 else { continue }
            let rad = min(CGFloat(Double(puff.rad) * halfH * focal / Double(depth)), cap)
            if rad < 0.6 { continue }
            let m = rad + 4
            if sp.x < -m || sp.x > size.width + m || sp.y < -m || sp.y > size.height + m { continue }
            sprites.append(Sprite(p: sp, r: rad, color: puff.color, op: puff.op, depth: depth))
        }
        sprites.sort { $0.depth > $1.depth }

        context.drawLayer { layer in
            layer.blendMode = .plusLighter
            for s in sprites {
                // 3-stop: a brighter, more defined core that falls off to the rim,
                // so the cloud's structure reads clearly instead of washing out.
                layer.fill(Path(ellipseIn: CGRect(x: s.p.x - s.r, y: s.p.y - s.r, width: s.r * 2, height: s.r * 2)),
                           with: .radialGradient(Gradient(colors: [s.color.opacity(s.op), s.color.opacity(s.op * 0.4), .clear]),
                                                 center: s.p, startRadius: 0, endRadius: s.r))
            }
            for w in embeddedStars {
                guard let (sp, depth) = project(w, viewProjection, size), depth > 0 else { continue }
                let dr = CGFloat(max(1.0, min(3.5, Double(physR) * 0.05 * halfH * focal / Double(depth))))
                layer.fill(Path(ellipseIn: CGRect(x: sp.x - dr * 3, y: sp.y - dr * 3, width: dr * 6, height: dr * 6)),
                           with: .radialGradient(Gradient(colors: [Color.white.opacity(0.5), .clear]),
                                                 center: sp, startRadius: 0, endRadius: dr * 3))
                layer.fill(Path(ellipseIn: CGRect(x: sp.x - dr, y: sp.y - dr, width: dr * 2, height: dr * 2)), with: .color(.white))
            }
        }
    }

    private func overlay(size: CGSize, viewProjection: simd_float4x4, safe: EdgeInsets) -> some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Compact control bar: navigation + flight stay inline; the view
                // toggles live behind one "Options" button that drops a panel down.
                HStack(spacing: 8) {
                    backButton
                    catalogButton
                    Spacer()
                    CircleIconButton(label: "View options", systemImage: "slider.horizontal.3",
                                     isActive: showOptions) {
                        withAnimation(.spring(duration: 0.3)) { showOptions.toggle() }
                    }
                    flyButton
                }
                .padding(.horizontal)
                .padding(.top, safe.top + 8)

                // Star count: a light, left-aligned label — the scale of the real
                // near-field star field, kept understated so it doesn't compete.
                HStack {
                    Text("\(stars.count.formatted()) stars")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                        .shadow(radius: 3)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 10)

                Spacer()

                if let selection {
                    selectionCard(selection)
                } else {
                    Text(flyMode ? "Drag to steer · two-finger drag up/down to set speed"
                                 : "Drag to orbit · pinch to zoom · tap a star or landmark")
                        .font(.caption).foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center).padding(.horizontal)
                }

                // Distance from Earth: faint, quiet text along the bottom — the
                // through-line of how far you've travelled, not a flashy badge.
                DistanceReadout(parsecs: cameraDistanceParsecs)
                    .padding(.top, 10)
            }
            .padding(.bottom, safe.bottom + 10)

            // The expandable options panel, dropping down from under its button.
            if showOptions {
                optionsPanel
                    .padding(.trailing)
                    .padding(.top, safe.top + 8 + Theme.controlSize + 6)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }

            if flyMode {
                // Steering anchor at screen centre.
                FlyReticle()

                // Persistent-speed feedback near the top; only shown while moving.
                if throttle != 0 {
                    VStack {
                        Spacer().frame(height: safe.top + 96)
                        SpeedReadout(throttle: throttle, maxSpeed: flySpeed)
                        Spacer()
                    }
                }

                // Invisible: adds a window-level two-finger pan recogniser that feeds
                // the throttle without blocking one-finger steering or taps.
                TwoFingerVerticalPan(throttle: $throttle, active: $throttling)
            }
        }
    }

    // MARK: Controls

    private var backButton: some View {
        CircleIconButton(label: "Back", systemImage: "chevron.left") { dismiss() }
    }
    private var catalogButton: some View {
        CircleIconButton(label: "Catalog", systemImage: "magnifyingglass") { showCatalog = true }
    }
    private var flyButton: some View {
        CircleIconButton(label: flyMode ? "Exit free flight" : "Free flight",
                         systemImage: flyMode ? "airplane.circle.fill" : "airplane",
                         tint: .green, isActive: flyMode) {
            flyMode ? exitFlyMode() : enterFlyMode()
        }
    }

    /// The drop-down of map view options — toggles stay open with a check; one-shot
    /// camera actions close the panel.
    private var optionsPanel: some View {
        let teal = Color(red: 0.4, green: 0.95, blue: 0.9)
        return VStack(spacing: 2) {
            optionRow("Milky Way", "sparkles", tint: .purple, toggle: true, isOn: showMilkyWay) {
                showMilkyWay.toggle()
            }
            optionRow("Planet hosts only", "globe.americas.fill", tint: teal, toggle: true, isOn: hostsOnly) {
                hostsOnly.toggle()
            }
            Divider().overlay(.white.opacity(0.12)).padding(.vertical, 2)
            optionRow("Centre on the Sun", "sun.max.fill", tint: Theme.accent, toggle: false, isOn: false) {
                closeOptions(); exitFlyMode(); animateCamera(to: .zero, distance: 220)
            }
            optionRow("Galaxy overview", "hurricane", tint: Theme.accent, toggle: false, isOn: false) {
                closeOptions(); exitFlyMode(); flyToGalaxy()
            }
        }
        .padding(8)
        .frame(width: 236)
        .luminousSurface()
    }

    private func optionRow(_ label: String, _ icon: String, tint: Color,
                           toggle: Bool, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isOn ? tint : .white.opacity(0.85))
                    .frame(width: 26)
                Text(label).font(.subheadline).foregroundStyle(.white)
                Spacer()
                if toggle {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isOn ? tint : .white.opacity(0.3))
                }
            }
            .padding(.vertical, 9).padding(.horizontal, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(toggle && isOn ? .isSelected : [])
    }

    private func closeOptions() {
        withAnimation(.spring(duration: 0.3)) { showOptions = false }
    }

    @ViewBuilder
    private func selectionCard(_ selection: MapSelection) -> some View {
        switch selection {
        case .sun:
            let sol = exo.byHost["Sol"] ?? SolarSystem.system
            card(title: "Sol", tint: .orange,
                 detail: "Our Sun · G2 V · home system", body: nil,
                 systemAction: { shownSystem = sol }) {
                exitFlyMode(); animateCamera(to: .zero, distance: 60)
            }
        case .star(let star):
            let system = star.hip.flatMap { exo.byHIP[$0] }
            let lightTravel = star.distanceParsecs > 0
                ? StarFacts.lightTravelSentence(distanceParsecs: star.distanceParsecs) : nil
            card(title: star.name, tint: .white, detail: starDetail(star), body: lightTravel,
                 systemAction: system.map { sys in { shownSystem = sys } }) { flyTo(star) }
        case .landmark(let lm):
            card(title: lm.name, tint: lm.type.color, detail: landmarkDetail(lm), body: lm.summary) { flyTo(lm) }
        }
    }

    private func starDetail(_ star: GalaxyStar) -> String {
        let ly = star.distanceParsecs * 3.2616
        var s = String(format: "%.1f ly · %.1f pc · mag %.1f", ly, star.distanceParsecs, star.magnitude)
        if let c = star.constellation { s += " · \(c)" }
        return s
    }

    private func landmarkDetail(_ lm: Landmark) -> String {
        let designation = lm.designation.map { "\($0) · " } ?? ""
        return "\(designation)\(lm.type.label) · \(formatDistance(lm.distanceLightYears)) ly"
    }

    private func formatDistance(_ ly: Double) -> String {
        ly >= 10000 ? String(format: "%.0fk", ly / 1000) : String(format: "%.0f", ly)
    }

    private func card(title: String, tint: Color, detail: String, body: String?,
                      systemAction: (() -> Void)? = nil, fly: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(.white)
                Spacer()
                Button { selection = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss \(title)")
            }
            .padding(.trailing, -10)   // pull the 44pt hit area back to the card edge
            Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
            if let body {
                Text(body).font(.caption).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 8) {
                Button(action: fly) {
                    Label("Fly here", systemImage: "paperplane.fill")
                        .font(.subheadline).frame(maxWidth: .infinity)
                }
                .buttonStyle(LuminousButtonStyle(tint: tint == .white ? Theme.accent : tint))
                if let systemAction {
                    Button(action: systemAction) {
                        Label("View planetary system", systemImage: "circle.dotted.circle")
                            .font(.subheadline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LuminousButtonStyle(tint: .cyan))
                }
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luminousSurface(tint == .white ? Theme.accent : tint)
        .padding(.horizontal)
    }

    // MARK: Camera

    private var lookDirection: SIMD3<Float> {
        SIMD3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
    }

    /// The camera's distance from Earth, in parsecs. Earth sits at the catalog
    /// origin (the Sun), so this is just the length of the eye position — the "how
    /// far have I travelled from home" readout.
    private var cameraDistanceParsecs: Float {
        let eyePosition = flyMode ? eye : target + distance * lookDirection
        return simd_length(eyePosition)
    }

    private func makeViewProjection(aspect: Float) -> simd_float4x4 {
        let dir = lookDirection
        let cameraEye: SIMD3<Float>
        let center: SIMD3<Float>
        if flyMode {
            cameraEye = eye
            center = eye - dir          // forward is -dir, matching orbit's look
        } else {
            cameraEye = target + distance * dir
            center = target
        }
        let view = lookAt(eye: cameraEye, center: center, up: SIMD3(0, 1, 0))
        let projection = perspective(fovy: fieldOfView, aspect: aspect, near: 0.05, far: 200000)
        return projection * view
    }

    // MARK: Free-fly

    private func enterFlyMode() {
        eye = target + distance * lookDirection   // start where the orbit camera was
        flyMode = true
        flyTask?.cancel()
        flyTask = Task { @MainActor in
            var last = Date()
            while !Task.isCancelled {
                let now = Date()
                let dt = Float(min(0.05, now.timeIntervalSince(last)))
                last = now
                if throttle != 0 {
                    // Square the throttle (keeping its sign) so low settings give
                    // fine, slow movement near a star and full throttle still crosses
                    // the galaxy quickly.
                    let speed = (throttle < 0 ? -1 : 1) * throttle * throttle * flySpeed
                    eye += (-lookDirection) * (speed * dt)
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func exitFlyMode() {
        guard flyMode else { return }
        target = eye - lookDirection * distance   // resume orbit around a point ahead
        flyMode = false
        throttle = 0
        throttling = false
        flyTask?.cancel()
    }

    private func project(_ position: SIMD3<Float>, _ viewProjection: simd_float4x4, _ size: CGSize) -> (CGPoint, Float)? {
        let clip = viewProjection * SIMD4<Float>(position, 1)
        guard clip.w > 0.0001 else { return nil }
        let ndcX = clip.x / clip.w, ndcY = clip.y / clip.w
        let point = CGPoint(x: Double((ndcX * 0.5 + 0.5)) * size.width,
                            y: Double((0.5 - ndcY * 0.5)) * size.height)
        return (point, clip.w)
    }

    private func flyTo(_ star: GalaxyStar) {
        exitFlyMode()
        animateCamera(to: star.position, distance: 40)
    }

    private func flyTo(_ landmark: Landmark) {
        exitFlyMode()
        animateCamera(to: landmark.positionParsecs, distance: landmark.suggestedViewDistance)
    }

    /// If opened with a focus (from the Catalog), select it and fly there once ready.
    private func applyInitialFocusIfNeeded() {
        guard !focusApplied, let focus else { return }
        switch focus {
        case .landmark(let lm):
            focusApplied = true
            selection = .landmark(lm)
            animateCamera(to: lm.positionParsecs, distance: lm.suggestedViewDistance, duration: 1.6)
        case .star(let id):
            guard let gs = stars.first(where: { $0.id == id }) else { return }   // wait for stars to build
            focusApplied = true
            selection = .star(gs)
            animateCamera(to: gs.position, distance: 40, duration: 1.6)
        }
    }

    /// Flies the camera out to a face-on view of the whole galaxy, centred on Sgr A*.
    private func flyToGalaxy() {
        let n = Galactic.north
        animateCamera(to: Galactic.centerPosition, distance: 42000,
                      yaw: atan2(n.x, n.z), pitch: asin(max(-1, min(1, n.y))), duration: 1.9)
    }

    /// Smoothly flies the camera to a new target/distance (and optional orientation)
    /// over `duration` seconds along an eased path, instead of teleporting. Driving
    /// the camera state per frame from a Task re-renders the Canvas without a
    /// persistent TimelineView.
    private func animateCamera(to newTarget: SIMD3<Float>, distance newDistance: Float,
                               yaw newYaw: Float? = nil, pitch newPitch: Float? = nil,
                               duration: Double = 1.2) {
        flightTask?.cancel()
        let startTarget = target
        let startDistance = distance
        let startYaw = yaw
        let startPitch = pitch
        let endPitch = newPitch ?? pitch
        var deltaYaw = (newYaw ?? yaw) - startYaw
        while deltaYaw > .pi { deltaYaw -= 2 * .pi }      // take the short way around
        while deltaYaw < -.pi { deltaYaw += 2 * .pi }
        flightTask = Task { @MainActor in
            let start = Date()
            while !Task.isCancelled {
                let raw = Float(min(1, Date().timeIntervalSince(start) / duration))
                let eased = raw * raw * (3 - 2 * raw)   // smoothstep
                target = startTarget + (newTarget - startTarget) * eased
                distance = startDistance + (newDistance - startDistance) * eased
                yaw = startYaw + deltaYaw * eased
                pitch = startPitch + (endPitch - startPitch) * eased
                zoomAnchor = distance
                if raw >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    // MARK: Gestures

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Ignore stray single-finger tracking while a two-finger throttle
                // gesture is in progress, so the view doesn't drift as you set speed.
                guard !throttling else { return }
                flightTask?.cancel()
                let dx = Float(value.translation.width - dragPrevious.width)
                let dy = Float(value.translation.height - dragPrevious.height)
                yaw -= dx * 0.005
                pitch = min(1.5, max(-1.5, pitch + dy * 0.005))
                dragPrevious = value.translation
            }
            .onEnded { _ in dragPrevious = .zero }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard !flyMode else { return }   // in fly mode two fingers set throttle, not zoom
                flightTask?.cancel()
                distance = min(60000, max(2, zoomAnchor / Float(value)))
            }
            .onEnded { _ in zoomAnchor = distance }
    }

    private func tapGesture(size: CGSize, viewProjection: simd_float4x4, hostHIPs: Set<Int>) -> some Gesture {
        SpatialTapGesture().onEnded { event in
            // Landmarks first — they're larger, fewer, and easier to mean to tap.
            var bestLandmark: (distance: CGFloat, landmark: Landmark)?
            for landmark in Landmarks.all {
                guard let (point, depth) = project(landmark.positionParsecs, viewProjection, size), depth > 0 else { continue }
                let d = hypot(point.x - event.location.x, point.y - event.location.y)
                if d < 26, bestLandmark == nil || d < bestLandmark!.distance { bestLandmark = (d, landmark) }
            }
            if let bestLandmark {
                selection = .landmark(bestLandmark.landmark)
                return
            }
            // The Sun (at the origin) — a real, always-present target with a rich system.
            if let (sunPoint, _) = project(.zero, viewProjection, size),
               hypot(sunPoint.x - event.location.x, sunPoint.y - event.location.y) < 22 {
                selection = .sun
                return
            }
            var bestStar: (distance: CGFloat, star: GalaxyStar)?
            for star in stars {
                if hostsOnly && !(star.hip.map { hostHIPs.contains($0) } ?? false) { continue }
                guard let (point, _) = project(star.position, viewProjection, size) else { continue }
                let d = hypot(point.x - event.location.x, point.y - event.location.y)
                if d < 22, bestStar == nil || d < bestStar!.distance { bestStar = (d, star) }
            }
            selection = bestStar.map { .star($0.star) }
        }
    }

    // MARK: Data

    private func buildStars() {
        guard stars.isEmpty, let catalog = store.catalog else { return }
        var result: [GalaxyStar] = []
        result.reserveCapacity(catalog.count)
        for star in catalog.stars {
            guard let parsecs = star.distanceParsecs, parsecs > 0, parsecs < 100_000 else { continue }
            let position: SIMD3<Float>
            if let p = star.position {
                position = SIMD3(Float(p.x), Float(p.y), Float(p.z))   // real HYG XYZ (parsecs)
            } else {
                let ra = Float(star.equatorial.rightAscension.radians)
                let dec = Float(star.equatorial.declination.radians)
                let d = Float(parsecs)
                position = SIMD3(d * cos(dec) * cos(ra), d * cos(dec) * sin(ra), d * sin(dec))
            }
            let absoluteMagnitude = star.apparentMagnitude - 5 * (log10(parsecs) - 1)
            result.append(GalaxyStar(
                id: star.id,
                hip: star.hipparcos,
                position: position,
                colorBucket: starBucket(star.colorIndex),
                baseSize: max(0.6, CGFloat(7 - absoluteMagnitude) * 0.32),
                magnitude: star.apparentMagnitude,
                distanceParsecs: parsecs,
                name: star.properName ?? star.bayerFlamsteed ?? star.hipparcos.map { "HIP \($0)" } ?? "Star \(star.id)",
                constellation: star.constellation
            ))
        }
        // Brightest (largest) first, so the level-of-detail cap keeps the prominent ones.
        result.sort { $0.baseSize > $1.baseSize }
        stars = result
    }

    /// Builds the stylized Milky Way at true scale: a full four-arm spiral disc
    /// centred on the galactic centre (~8.2 kpc from the Sun), so our real
    /// near-field stars form just a small local sector near the rim. Spiral arms,
    /// a diffuse inter-arm disc, and a bright central bulge. Pure art, not
    /// catalogued — the real stars render in front of it.
    private func buildBackdrop() {
        guard backdrop.isEmpty else { return }
        var rng = SeededGenerator(seed: 99)
        func rand(_ a: Float, _ b: Float) -> Float { Float(Double.random(in: Double(a)...Double(b), using: &rng)) }
        func gaussian() -> Float {
            let u1 = Double.random(in: 1e-6...1, using: &rng)
            let u2 = Double.random(in: 0...1, using: &rng)
            return Float((-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2))
        }

        let axisA = Galactic.center        // in-plane basis vectors at the centre
        let axisB = Galactic.inPlane
        let up = Galactic.north
        let centre = Galactic.centerPosition
        func place(_ x: Float, _ y: Float, _ h: Float) -> SIMD3<Float> {
            centre + x * axisA + y * axisB + h * up
        }

        let armBucket = 0, hiiBucket = 1, discBucket = 2, bulgeBucket = 3

        let rMax: Float = 15000
        let rInner: Float = 2400   // arms emanate from the ends of the bar
        let arms = 4
        let k: Float = 0.22        // logarithmic-spiral winding (~1.3 turns)

        // Spiral angle for a given galactocentric radius.
        func spiralAngle(_ r: Float) -> Float { Float(log(Double(r / rInner))) / k }

        var points: [BackdropPoint] = []

        // Two major arms (from the bar ends) + two minor arms, like the real galaxy.
        // Counts are kept modest (and brighter per point) for rendering performance.
        for armIndex in 0..<arms {
            let offset = Float(armIndex) * (.pi / 2)
            let major = (armIndex % 2 == 0)
            // Denser + smaller points read as smooth arm structure rather than
            // chunky dots; the bloom pass fuses them into a continuous lane.
            let starCount = major ? 4200 : 2300
            let knotCount = major ? 150 : 80
            let weight: Float = major ? 1.0 : 0.6
            for _ in 0..<starCount {
                let r = rInner + rand(0, 1) * (rMax - rInner)
                let rr = r + gaussian() * (r * 0.045 + 200)
                let angle = spiralAngle(r) + offset + gaussian() * 0.085
                let h = gaussian() * (115 + r * 0.010)
                let bright = max(0.07, 0.40 - 0.24 * (r / rMax)) * weight
                points.append(BackdropPoint(
                    position: place(cos(angle) * rr, sin(angle) * rr, h),
                    colorBucket: armBucket,
                    baseOpacity: Double(bright) * Double(rand(0.45, 1)),
                    size: CGFloat(rand(0.5, 1.3))))
            }
            // Pink HII regions studding the arms — the iconic star-forming knots.
            for _ in 0..<knotCount {
                let r = rInner + rand(0.05, 1) * (rMax - rInner)
                let angle = spiralAngle(r) + offset + gaussian() * 0.05
                let cx = cos(angle) * r, cy = sin(angle) * r
                points.append(BackdropPoint(
                    position: place(cx + gaussian() * 170, cy + gaussian() * 170, gaussian() * 110),
                    colorBucket: hiiBucket,
                    baseOpacity: Double(rand(0.28, 0.6)) * Double(weight),
                    size: CGFloat(rand(0.8, 1.8))))
            }
        }

        // Diffuse disc, exponential falloff — fills between the arms with a faint haze.
        for _ in 0..<4500 {
            let r = sqrt(rand(0, 1)) * rMax
            let angle = rand(0, 2 * .pi)
            let h = gaussian() * (105 + r * 0.010)
            let bright = max(0.025, 0.13 * exp(-r / 8000))
            points.append(BackdropPoint(
                position: place(cos(angle) * r, sin(angle) * r, h),
                colorBucket: discBucket,
                baseOpacity: Double(bright) * Double(rand(0.4, 1)),
                size: CGFloat(rand(0.45, 1.0))))
        }

        // Central bar + bulge — warm, bright, elongated (the Milky Way is a barred spiral).
        for _ in 0..<4200 {
            let x = gaussian() * 2700      // elongated along axisA → the bar
            let y = gaussian() * 1050
            let z = gaussian() * 650
            let d = (x * x / (2700 * 2700) + y * y / (1050 * 1050) + z * z / (650 * 650)).squareRoot()
            let opacity = min(0.85, max(0.10, 0.85 - Double(d) * 0.66))
            points.append(BackdropPoint(
                position: place(x, y, z),
                colorBucket: bulgeBucket,
                baseOpacity: opacity * Double(rand(0.55, 1)),
                size: CGFloat(rand(0.6, 1.6))))
        }

        backdrop = points
    }

    private func starBucket(_ colorIndex: Double?) -> Int {
        guard let ci = colorIndex else { return 2 }
        switch ci {
        case ..<0.0: return 0
        case ..<0.3: return 1
        case ..<0.6: return 2
        case ..<1.0: return 3
        case ..<1.5: return 4
        default:     return 5
        }
    }
}

private struct GalaxyStar: Identifiable {
    let id: Int
    let hip: Int?
    let position: SIMD3<Float>      // parsecs, equatorial, Sun at origin
    let colorBucket: Int           // index into starPalette
    let baseSize: CGFloat
    let magnitude: Double
    let distanceParsecs: Double
    let name: String
    let constellation: String?
}

/// Discrete palettes let us batch thousands of points into a handful of fills.
private let starPalette: [Color] = [
    Color(red: 0.70, green: 0.80, blue: 1.0),    // 0 hot blue
    Color(red: 0.86, green: 0.91, blue: 1.0),    // 1 blue-white
    .white,                                       // 2
    Color(red: 1.0, green: 0.95, blue: 0.84),    // 3 yellow-white
    Color(red: 1.0, green: 0.85, blue: 0.65),    // 4 orange
    Color(red: 1.0, green: 0.76, blue: 0.60),    // 5 red
]

private let backdropPalette: [Color] = [
    Color(red: 0.52, green: 0.66, blue: 1.0),    // 0 arm — cool blue (outer)
    Color(red: 1.0, green: 0.92, blue: 0.80),    // 1 arm — warm white (inner)
    Color(red: 1.0, green: 0.45, blue: 0.62),    // 2 HII knot (pink star-forming)
    Color(red: 0.56, green: 0.66, blue: 0.95),   // 3 disc haze
    Color(red: 1.0, green: 0.83, blue: 0.52),    // 4 bar/bulge (warm gold)
    Color(red: 1.0, green: 0.95, blue: 0.86),    // 5 halo (pale gold-white)
    Color(red: 0.62, green: 0.82, blue: 1.0),    // 6 young blue clusters at arm tips
]

/// Dust-lane tint — drawn with normal blending over the bloom to subtract light,
/// carving the dark veins that thread a galaxy's arms.
private let backdropDustColor = Color(red: 0.05, green: 0.03, blue: 0.02)

// Eight evenly-spaced levels (level i ≈ midpoint of its 1/8 band) — smoother than
// the old four-step quantisation, which banded the disc haze.
private let backdropOpacityLevels: [Double] = [0.0625, 0.1875, 0.3125, 0.4375, 0.5625, 0.6875, 0.8125, 0.9375]

/// Faint crosshair marking the centre of the screen — the point you're flying
/// toward and steering around in free-fly mode.
private struct FlyReticle: View {
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.22), lineWidth: 1).frame(width: 26, height: 26)
            Rectangle().fill(.white.opacity(0.28)).frame(width: 1, height: 9)
            Rectangle().fill(.white.opacity(0.28)).frame(width: 9, height: 1)
        }
        .allowsHitTesting(false)
    }
}

/// Non-interactive readout of how far the camera is from Earth (the catalog
/// origin). Always visible — the through-line that keeps the galaxy's scale legible
/// as you fly from the Solar neighbourhood out toward the galactic core.
private struct DistanceReadout: View {
    let parsecs: Float

    var body: some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.38))
            .shadow(radius: 3)
            .allowsHitTesting(false)
    }

    private var text: String {
        let pc = Double(parsecs)
        if pc < 0.05 { return "At Earth" }
        let ly = pc * Astrophysics.lightYearsPerParsec
        return "\(format(ly)) ly from Earth"
    }

    private func format(_ ly: Double) -> String {
        switch ly {
        case 1_000_000...: return String(format: "%.1fM", ly / 1_000_000)
        case 10_000...: return String(format: "%.0fk", ly / 1_000)
        case 100...: return String(format: "%.0f", ly)
        case 1...: return String(format: "%.0f", ly)
        default: return String(format: "%.2f", ly)
        }
    }
}

/// Non-interactive speed feedback for free-fly: shows the current throttle as a
/// percentage and the resulting speed. Green forward, orange in reverse.
private struct SpeedReadout: View {
    let throttle: Float
    let maxSpeed: Float

    var body: some View {
        let magnitude = throttle * throttle                 // matches the movement curve
        let pct = Int((magnitude * 100).rounded())
        let speed = magnitude * maxSpeed
        let forward = throttle >= 0
        HStack(spacing: 6) {
            Image(systemName: forward ? "chevron.up" : "chevron.down")
                .font(.caption2.weight(.bold))
            Text("\(pct)%").font(.caption.monospacedDigit().weight(.semibold))
            Text(String(format: "· %.0f pc/s", speed))
                .font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.6))
        }
        .foregroundStyle(forward ? Color.green : Color.orange)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .allowsHitTesting(false)
    }
}

/// Bridges a window-level two-finger vertical `UIPanGestureRecognizer` to the
/// throttle. The recogniser lives on the window (not this view) and requires
/// exactly two touches, so it never competes with SwiftUI's one-finger steer/tap
/// gestures. The view itself is transparent to touches (`hitTest` returns nil).
/// Dragging up increases the throttle, down decreases/reverses it; the value
/// persists when you let go (cruise control), with a small detent at zero.
private struct TwoFingerVerticalPan: UIViewRepresentable {
    @Binding var throttle: Float
    @Binding var active: Bool
    var sensitivity: Float = 0.0065   // throttle units per point of vertical drag

    func makeUIView(context: Context) -> PassthroughPanView {
        let view = PassthroughPanView()
        view.pan.addTarget(context.coordinator, action: #selector(Coordinator.handle(_:)))
        view.pan.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: PassthroughPanView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: TwoFingerVerticalPan
        init(_ parent: TwoFingerVerticalPan) { self.parent = parent }

        @objc func handle(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                parent.active = true
            case .changed:
                let dy = Float(gesture.translation(in: gesture.view).y)
                gesture.setTranslation(.zero, in: gesture.view)   // accumulate incrementally
                var next = parent.throttle - dy * parent.sensitivity   // up (dy<0) → faster
                next = max(-1, min(1, next))
                if abs(next) < 0.04 { next = 0 }                  // detent at rest
                parent.throttle = next
            case .ended, .cancelled, .failed:
                parent.active = false
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

/// A zero-cost passthrough view that owns a two-finger pan recogniser and parks
/// it on the window so it sees touches landing anywhere on the map, while letting
/// every touch fall through to the SwiftUI content beneath it.
final class PassthroughPanView: UIView {
    let pan: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer()
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        return pan
    }()

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        pan.view?.removeGestureRecognizer(pan)
        window?.addGestureRecognizer(pan)
    }
}

/// A faint, non-interactive point making up the stylized Milky Way backdrop.
private struct BackdropPoint {
    let position: SIMD3<Float>
    let colorBucket: Int           // index into backdropPalette
    let baseOpacity: Double
    let size: CGFloat
}

// MARK: - Galactic frame (equatorial coordinates, parsecs, Sun at origin)

private func equatorialUnit(_ raDeg: Double, _ decDeg: Double) -> SIMD3<Float> {
    let ra = Float(raDeg * .pi / 180), dec = Float(decDeg * .pi / 180)
    return SIMD3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))
}

private enum Galactic {
    static let sunDistance: Float = 8178                       // pc, Sun → galactic centre
    static let north = equatorialUnit(192.859, 27.128)         // galactic north pole
    static let center = equatorialUnit(266.405, -28.936)       // toward the galactic centre (b = 0)
    static let inPlane = simd_normalize(simd_cross(north, center))
    static var centerPosition: SIMD3<Float> { center * sunDistance }
}

// MARK: - 3D matrix helpers

private func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
    let f = simd_normalize(center - eye)
    let s = simd_normalize(simd_cross(f, up))
    let u = simd_cross(s, f)
    return simd_float4x4(columns: (
        SIMD4(s.x, u.x, -f.x, 0),
        SIMD4(s.y, u.y, -f.y, 0),
        SIMD4(s.z, u.z, -f.z, 0),
        SIMD4(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)
    ))
}

private func perspective(fovy: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
    let yScale = 1 / tan(fovy * 0.5)
    let xScale = yScale / aspect
    let zScale = far / (near - far)
    return simd_float4x4(columns: (
        SIMD4(xScale, 0, 0, 0),
        SIMD4(0, yScale, 0, 0),
        SIMD4(0, 0, zScale, -1),
        SIMD4(0, 0, zScale * near, 0)
    ))
}
