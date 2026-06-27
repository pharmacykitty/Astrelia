import SwiftUI
import simd
import CelestialCore

/// A 3D fly-through of the real local star field (HYG positions, in parsecs, with
/// the Sun at the origin). Drag to orbit, pinch to zoom, tap a star to inspect it.
/// This is the foundation of the flagship Galaxy Map; the stylized Milky Way
/// backdrop and exoplanets build on top of it.
struct GalaxyMapView: View {
    let store: StarCatalogStore

    @State private var stars: [GalaxyStar] = []
    @State private var backdrop: [BackdropPoint] = []   // stylized Milky Way (art, not catalogued)
    @State private var flightTask: Task<Void, Never>?

    // Orbit camera (parsecs).
    @State private var yaw: Float = 0.6
    @State private var pitch: Float = 0.35
    @State private var distance: Float = 220
    @State private var target = SIMD3<Float>(0, 0, 0)

    @State private var dragPrevious: CGSize = .zero
    @State private var zoomAnchor: Float = 220
    @State private var selection: GalaxyStar?

    private let fieldOfView: Float = 0.9   // radians (~51°)

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let viewProjection = makeViewProjection(aspect: Float(size.width / max(size.height, 1)))

            ZStack {
                LinearGradient(colors: [Color(red: 0.01, green: 0.01, blue: 0.05), .black],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                Canvas { context, _ in
                    draw(in: context, size: size, viewProjection: viewProjection)
                }

                overlay(size: size, viewProjection: viewProjection)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .simultaneousGesture(zoomGesture)
            .simultaneousGesture(tapGesture(size: size, viewProjection: viewProjection))
        }
        .navigationTitle("Galaxy Map")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: store.catalog?.count ?? 0) { buildStars(); buildBackdrop() }
        .onDisappear { flightTask?.cancel() }
    }

    // MARK: Rendering

    private func draw(in context: GraphicsContext, size: CGSize, viewProjection: simd_float4x4) {
        // Stylized Milky Way, drawn first so real stars sit in front of it.
        for point in backdrop {
            guard let (p, depth) = project(point.position, viewProjection, size) else { continue }
            if p.x < -2 || p.x > size.width + 2 || p.y < -2 || p.y > size.height + 2 { continue }
            let perspective = min(3.0, max(0.7, Double(900 / depth)))
            let radius = point.size * CGFloat(perspective)
            context.fill(
                Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(point.color.opacity(point.baseOpacity))
            )
        }

        for star in stars {
            guard let (point, depth) = project(star.position, viewProjection, size) else { continue }
            if point.x < -4 || point.x > size.width + 4 || point.y < -4 || point.y > size.height + 4 { continue }

            let perspective = min(3.0, max(0.4, 150 / depth))
            let radius = max(0.5, star.baseSize * CGFloat(perspective))
            let opacity = min(1.0, max(0.2, Double(320 / depth)))
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(star.color.opacity(opacity))
            )
        }

        // The Sun at the origin.
        if let (sunPoint, _) = project(.zero, viewProjection, size) {
            context.fill(Path(ellipseIn: CGRect(x: sunPoint.x - 7, y: sunPoint.y - 7, width: 14, height: 14)),
                         with: .color(.orange.opacity(0.25)))
            context.fill(Path(ellipseIn: CGRect(x: sunPoint.x - 3, y: sunPoint.y - 3, width: 6, height: 6)),
                         with: .color(.orange))
            context.draw(Text("Sol").font(.system(size: 10, weight: .semibold)).foregroundStyle(.orange),
                         at: CGPoint(x: sunPoint.x, y: sunPoint.y + 14))
        }

        // Sagittarius A* — the galactic centre.
        if let (p, depth) = project(Galactic.centerPosition, viewProjection, size), depth > 0 {
            let glow = Color(red: 1.0, green: 0.9, blue: 0.72)
            context.fill(Path(ellipseIn: CGRect(x: p.x - 18, y: p.y - 18, width: 36, height: 36)),
                         with: .color(glow.opacity(0.10)))
            context.fill(Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)),
                         with: .color(glow.opacity(0.22)))
            context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                         with: .color(.white))
            context.draw(Text("Sgr A*").font(.system(size: 10, weight: .semibold)).foregroundStyle(glow),
                         at: CGPoint(x: p.x, y: p.y + 16))
        }

        // Selection ring + label.
        if let selection, let (point, _) = project(selection.position, viewProjection, size) {
            context.stroke(Path(ellipseIn: CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24)),
                           with: .color(.white), lineWidth: 1.5)
        }
    }

    private func overlay(size: CGSize, viewProjection: simd_float4x4) -> some View {
        VStack {
            HStack(spacing: 8) {
                Text("\(stars.count) stars")
                    .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button { animateCamera(to: .zero, distance: 220) } label: {
                    Label("Sol", systemImage: "sun.max.fill").font(.caption)
                }
                .buttonStyle(.bordered).tint(.white)
                Button { flyToGalaxy() } label: {
                    Label("Galaxy", systemImage: "hurricane").font(.caption)
                }
                .buttonStyle(.bordered).tint(.white)
            }
            .padding(.horizontal)

            Spacer()

            if let selection {
                selectionCard(selection)
            } else {
                Text("Drag to orbit · pinch to zoom · tap a star")
                    .font(.caption).foregroundStyle(.white.opacity(0.45))
                    .padding(.bottom, 8)
            }
        }
        .padding(.vertical, 8)
    }

    private func selectionCard(_ star: GalaxyStar) -> some View {
        let lightYears = star.distanceParsecs * 3.2616
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(star.name).font(.title3.weight(.semibold)).foregroundStyle(.white)
                Spacer()
                Button { selection = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(.white.opacity(0.5))
            }
            Text(String(format: "%.1f ly  ·  %.1f pc  ·  mag %.1f", lightYears, star.distanceParsecs, star.magnitude))
                .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
            if let constellation = star.constellation {
                Text(constellation).font(.caption2).foregroundStyle(.white.opacity(0.5))
            }
            Button {
                flyTo(star)
            } label: {
                Label("Fly here", systemImage: "paperplane.fill").font(.subheadline)
            }
            .buttonStyle(.borderedProminent).tint(.blue)
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: Camera

    private func makeViewProjection(aspect: Float) -> simd_float4x4 {
        let direction = SIMD3<Float>(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
        let eye = target + distance * direction
        let view = lookAt(eye: eye, center: target, up: SIMD3(0, 1, 0))
        let projection = perspective(fovy: fieldOfView, aspect: aspect, near: 0.05, far: 200000)
        return projection * view
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
        animateCamera(to: star.position, distance: 40)
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
                flightTask?.cancel()
                distance = min(60000, max(2, zoomAnchor / Float(value)))
            }
            .onEnded { _ in zoomAnchor = distance }
    }

    private func tapGesture(size: CGSize, viewProjection: simd_float4x4) -> some Gesture {
        SpatialTapGesture().onEnded { event in
            var best: (distance: CGFloat, star: GalaxyStar)?
            for star in stars {
                guard let (point, _) = project(star.position, viewProjection, size) else { continue }
                let d = hypot(point.x - event.location.x, point.y - event.location.y)
                if d < 24, best == nil || d < best!.distance { best = (d, star) }
            }
            selection = best?.star
        }
    }

    // MARK: Data

    private func buildStars() {
        guard stars.isEmpty, let catalog = store.catalog else { return }
        var result: [GalaxyStar] = []
        result.reserveCapacity(catalog.count)
        for star in catalog.stars {
            guard let parsecs = star.distanceParsecs, parsecs > 0, parsecs < 100_000 else { continue }
            let ra = Float(star.equatorial.rightAscension.radians)
            let dec = Float(star.equatorial.declination.radians)
            let d = Float(parsecs)
            let position = SIMD3<Float>(d * cos(dec) * cos(ra), d * cos(dec) * sin(ra), d * sin(dec))
            let absoluteMagnitude = star.apparentMagnitude - 5 * (log10(parsecs) - 1)
            result.append(GalaxyStar(
                id: star.id,
                position: position,
                color: starColor(star.colorIndex),
                baseSize: max(0.6, CGFloat(7 - absoluteMagnitude) * 0.32),
                magnitude: star.apparentMagnitude,
                distanceParsecs: parsecs,
                name: star.properName ?? star.bayerFlamsteed ?? star.hipparcos.map { "HIP \($0)" } ?? "Star \(star.id)",
                constellation: star.constellation
            ))
        }
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

        let armColor = Color(red: 0.80, green: 0.87, blue: 1.0)   // bluish young arm stars
        let discColor = Color(red: 0.93, green: 0.91, blue: 0.85) // diffuse disc
        let bulgeColor = Color(red: 1.0, green: 0.84, blue: 0.55) // warm central bulge

        let rMax: Float = 16000
        let arms = 4
        let pitch: Float = 0.23   // logarithmic-spiral tightness

        var points: [BackdropPoint] = []

        // Spiral arms — bright, define the structure.
        for armIndex in 0..<arms {
            let offset = Float(armIndex) * (2 * .pi / Float(arms))
            for _ in 0..<1700 {
                let theta = rand(0, 1) * 6.0
                let r = 600 * exp(pitch * theta)
                if r > rMax { continue }
                let rr = r + gaussian() * (r * 0.10 + 250)
                let angle = theta + offset + gaussian() * 0.10
                let h = gaussian() * (180 + r * 0.012)
                points.append(BackdropPoint(
                    position: place(cos(angle) * rr, sin(angle) * rr, h),
                    baseOpacity: Double(rand(0.30, 0.65)),
                    size: CGFloat(rand(0.7, 1.7)),
                    color: armColor))
            }
        }

        // Diffuse disc filling between the arms.
        for _ in 0..<3600 {
            let r = sqrt(rand(0, 1)) * rMax
            let angle = rand(0, 2 * .pi)
            let h = gaussian() * (160 + r * 0.012)
            points.append(BackdropPoint(
                position: place(cos(angle) * r, sin(angle) * r, h),
                baseOpacity: Double(rand(0.05, 0.18)),
                size: CGFloat(rand(0.5, 1.1)),
                color: discColor))
        }

        // Central bulge — dense, warm, brightest; a flattened spheroid.
        for _ in 0..<2800 {
            let x = gaussian() * 1700, y = gaussian() * 1700, z = gaussian() * 850
            let dist = (x * x + y * y + z * z).squareRoot()
            let opacity = min(0.85, max(0.15, 0.85 - Double(dist) / 3200))
            points.append(BackdropPoint(
                position: place(x, y, z),
                baseOpacity: opacity * Double(rand(0.6, 1)),
                size: CGFloat(rand(0.7, 1.8)),
                color: bulgeColor))
        }

        backdrop = points
    }

    private func starColor(_ colorIndex: Double?) -> Color {
        guard let ci = colorIndex else { return .white }
        switch ci {
        case ..<0.0: return Color(red: 0.70, green: 0.80, blue: 1.0)
        case ..<0.3: return Color(red: 0.86, green: 0.91, blue: 1.0)
        case ..<0.6: return .white
        case ..<1.0: return Color(red: 1.0, green: 0.95, blue: 0.84)
        case ..<1.5: return Color(red: 1.0, green: 0.85, blue: 0.65)
        default:     return Color(red: 1.0, green: 0.76, blue: 0.60)
        }
    }
}

private struct GalaxyStar: Identifiable {
    let id: Int
    let position: SIMD3<Float>      // parsecs, equatorial, Sun at origin
    let color: Color
    let baseSize: CGFloat
    let magnitude: Double
    let distanceParsecs: Double
    let name: String
    let constellation: String?
}

/// A faint, non-interactive point making up the stylized Milky Way backdrop.
private struct BackdropPoint {
    let position: SIMD3<Float>
    let baseOpacity: Double
    let size: CGFloat
    let color: Color
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
