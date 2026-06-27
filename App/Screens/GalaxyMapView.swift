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
            let fade = min(1.0, max(0.12, Double(2500 / depth)))
            context.fill(
                Path(ellipseIn: CGRect(x: p.x - point.size, y: p.y - point.size, width: point.size * 2, height: point.size * 2)),
                with: .color(point.color.opacity(point.baseOpacity * fade))
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

        // Selection ring + label.
        if let selection, let (point, _) = project(selection.position, viewProjection, size) {
            context.stroke(Path(ellipseIn: CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24)),
                           with: .color(.white), lineWidth: 1.5)
        }
    }

    private func overlay(size: CGSize, viewProjection: simd_float4x4) -> some View {
        VStack {
            HStack {
                Text("\(stars.count) stars")
                    .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button {
                    animateCamera(to: .zero, distance: 220)
                } label: {
                    Label("Recenter", systemImage: "scope").font(.caption)
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

    /// Smoothly flies the camera to a new target/distance over `duration` seconds
    /// (eased straight-line path) instead of teleporting. Driving `target`/`distance`
    /// per frame from a Task re-renders the Canvas without a persistent TimelineView.
    private func animateCamera(to newTarget: SIMD3<Float>, distance newDistance: Float, duration: Double = 1.2) {
        flightTask?.cancel()
        let startTarget = target
        let startDistance = distance
        flightTask = Task { @MainActor in
            let start = Date()
            while !Task.isCancelled {
                let raw = Float(min(1, Date().timeIntervalSince(start) / duration))
                let eased = raw * raw * (3 - 2 * raw)   // smoothstep
                target = startTarget + (newTarget - startTarget) * eased
                distance = startDistance + (newDistance - startDistance) * eased
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
                distance = min(8000, max(2, zoomAnchor / Float(value)))
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

    /// Builds the stylized Milky Way: a faint flattened disc of points in the real
    /// galactic plane (so the band sits where it actually is relative to the stars)
    /// plus a warmer bulge toward the galactic centre. Pure art, not catalogued —
    /// the real near-field stars render in front of it.
    private func buildBackdrop() {
        guard backdrop.isEmpty else { return }
        var rng = SeededGenerator(seed: 99)
        func rand(_ a: Float, _ b: Float) -> Float { Float(Double.random(in: Double(a)...Double(b), using: &rng)) }
        func gaussian() -> Float {
            let u1 = Double.random(in: 1e-6...1, using: &rng)
            let u2 = Double.random(in: 0...1, using: &rng)
            return Float((-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2))
        }
        func unit(_ raDeg: Double, _ decDeg: Double) -> SIMD3<Float> {
            let ra = Float(raDeg * .pi / 180), dec = Float(decDeg * .pi / 180)
            return SIMD3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))
        }
        // Galactic frame in equatorial coordinates.
        let gNorth = unit(192.859, 27.128)      // galactic north pole
        let gCenter = unit(266.405, -28.936)    // direction of the galactic centre (b = 0)
        let gV = simd_normalize(simd_cross(gNorth, gCenter))
        let cream = Color(red: 0.95, green: 0.93, blue: 0.86)
        let gold = Color(red: 1.0, green: 0.86, blue: 0.62)

        var points: [BackdropPoint] = []
        // The disc — denser/brighter toward the galactic centre to suggest the band.
        for _ in 0..<2800 {
            let theta = rand(0, 2 * .pi)
            let r = sqrt(rand(0, 1)) * 6000 + 250
            let h = gaussian() * 130
            let planeDir = cos(theta) * gCenter + sin(theta) * gV
            let pos = r * planeDir + h * gNorth
            let centerward = 0.5 + 0.5 * simd_dot(planeDir, gCenter)
            points.append(BackdropPoint(
                position: pos,
                baseOpacity: Double(0.05 + 0.20 * centerward) * Double(rand(0.4, 1)),
                size: CGFloat(rand(0.5, 1.5)),
                color: cream))
        }
        // The central bulge, far away toward the galactic centre.
        for _ in 0..<900 {
            let dir = simd_normalize(gCenter + SIMD3(gaussian(), gaussian(), gaussian()) * 0.18)
            let pos = dir * (7000 + gaussian() * 1400)
            points.append(BackdropPoint(
                position: pos,
                baseOpacity: Double(rand(0.08, 0.30)),
                size: CGFloat(rand(0.6, 1.7)),
                color: gold))
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
