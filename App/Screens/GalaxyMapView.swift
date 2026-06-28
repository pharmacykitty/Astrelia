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
    var focus: GalaxyMapFocus? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var focusApplied = false
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

    // Free-fly camera: a free eye position + look direction, moved by a throttle.
    @State private var flyMode = false
    @State private var eye = SIMD3<Float>(0, 0, 0)
    @State private var throttle: Float = 0
    @State private var flyTask: Task<Void, Never>?
    private let flySpeed: Float = 2200   // parsecs/second at full throttle

    @State private var selection: MapSelection?

    /// What the user has tapped — a real star or a curated landmark.
    private enum MapSelection {
        case star(GalaxyStar)
        case landmark(Landmark)

        var position: SIMD3<Float> {
            switch self {
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

            ZStack {
                LinearGradient(colors: [Color(red: 0.01, green: 0.01, blue: 0.05), .black],
                               startPoint: .top, endPoint: .bottom)

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
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: store.catalog?.count ?? 0) {
            buildStars(); buildBackdrop(); applyInitialFocusIfNeeded()
        }
        .onDisappear { flightTask?.cancel(); flyTask?.cancel() }
    }

    /// Device safe-area insets, read directly since the map ignores the safe area
    /// (so the galaxy fills the screen) but the controls should still stay clear.
    private var safeInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
    }

    // MARK: Rendering

    private func draw(in context: GraphicsContext, size: CGSize, viewProjection: simd_float4x4) {
        // Stylized Milky Way: drawn into a blurred, additively-blended layer so the
        // points melt into luminous arms, bar and bulge instead of reading as dots.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 3.5))
            layer.blendMode = .plusLighter
            for point in backdrop {
                guard let (p, depth) = project(point.position, viewProjection, size) else { continue }
                if p.x < -6 || p.x > size.width + 6 || p.y < -6 || p.y > size.height + 6 { continue }
                let perspective = min(3.2, max(0.8, Double(900 / depth)))
                let radius = point.size * CGFloat(perspective)
                layer.fill(
                    Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(point.color.opacity(point.baseOpacity))
                )
            }
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

        // Deep-sky landmarks — nebulae, clusters, black holes, satellite galaxies.
        var labelRects: [CGRect] = []
        for landmark in Landmarks.all {
            guard let (p, depth) = project(landmark.positionParsecs, viewProjection, size), depth > 0 else { continue }
            if p.x < -24 || p.x > size.width + 24 || p.y < -24 || p.y > size.height + 24 { continue }
            let color = landmark.type.color
            let big = landmark.type == .blackHole || landmark.type == .galaxy
            let outer: CGFloat = big ? 13 : 9
            context.fill(Path(ellipseIn: CGRect(x: p.x - outer, y: p.y - outer, width: outer * 2, height: outer * 2)),
                         with: .color(color.opacity(0.13)))
            context.fill(Path(ellipseIn: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)),
                         with: .color(color.opacity(0.45)))
            context.fill(Path(ellipseIn: CGRect(x: p.x - 1.8, y: p.y - 1.8, width: 3.6, height: 3.6)),
                         with: .color(.white.opacity(0.95)))

            let text = Text(landmark.name).font(.system(size: 9, weight: .medium)).foregroundStyle(color.opacity(0.95))
            let resolved = context.resolve(text)
            let m = resolved.measure(in: CGSize(width: 160, height: 40))
            let rect = CGRect(x: p.x - m.width / 2, y: p.y + 11 - m.height / 2, width: m.width, height: m.height)
            if rect.minX > 2, rect.maxX < size.width - 2, rect.minY > 2, rect.maxY < size.height - 2,
               !labelRects.contains(where: { $0.intersects(rect) }) {
                labelRects.append(rect.insetBy(dx: -3, dy: -3))
                context.draw(resolved, at: CGPoint(x: p.x, y: p.y + 11))
            }
        }

        // Selection ring + label.
        if let selection, let (point, _) = project(selection.position, viewProjection, size) {
            context.stroke(Path(ellipseIn: CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24)),
                           with: .color(.white), lineWidth: 1.5)
        }
    }

    private func overlay(size: CGSize, viewProjection: simd_float4x4) -> some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Text("\(stars.count) stars")
                        .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Button { exitFlyMode(); animateCamera(to: .zero, distance: 220) } label: {
                        Image(systemName: "sun.max.fill").frame(width: 30, height: 24)
                    }
                    .buttonStyle(.bordered).tint(.white)
                    Button { exitFlyMode(); flyToGalaxy() } label: {
                        Image(systemName: "hurricane").frame(width: 30, height: 24)
                    }
                    .buttonStyle(.bordered).tint(.white)
                    Button { flyMode ? exitFlyMode() : enterFlyMode() } label: {
                        Image(systemName: flyMode ? "airplane.circle.fill" : "airplane").frame(width: 30, height: 24)
                    }
                    .buttonStyle(.bordered).tint(flyMode ? .green : .white)
                }
                .padding(.horizontal)
                .padding(.top, safeInsets.top + 4)

                Spacer()

                if let selection {
                    selectionCard(selection)
                } else {
                    Text(flyMode ? "Drag to aim · use the throttle to fly"
                                 : "Drag to orbit · pinch to zoom · tap a star or landmark")
                        .font(.caption).foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center).padding(.horizontal)
                }
            }
            .padding(.bottom, safeInsets.bottom + 10)

            if flyMode {
                HStack {
                    Spacer()
                    ThrottleControl(throttle: $throttle).padding(.trailing, 14)
                }
            }
        }
    }

    @ViewBuilder
    private func selectionCard(_ selection: MapSelection) -> some View {
        switch selection {
        case .star(let star): card(title: star.name, tint: .white, detail: starDetail(star), body: nil) { flyTo(star) }
        case .landmark(let lm): card(title: lm.name, tint: lm.type.color, detail: landmarkDetail(lm), body: lm.summary) { flyTo(lm) }
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

    private func card(title: String, tint: Color, detail: String, body: String?, fly: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(.white)
                Spacer()
                Button { selection = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(.white.opacity(0.5))
            }
            Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
            if let body {
                Text(body).font(.caption).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
            }
            Button(action: fly) {
                Label("Fly here", systemImage: "paperplane.fill").font(.subheadline)
            }
            .buttonStyle(.borderedProminent).tint(tint == .white ? .blue : tint)
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: Camera

    private var lookDirection: SIMD3<Float> {
        SIMD3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
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
                    eye += (-lookDirection) * (throttle * flySpeed * dt)
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
            var bestStar: (distance: CGFloat, star: GalaxyStar)?
            for star in stars {
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

        let armColor = Color(red: 0.72, green: 0.82, blue: 1.0)   // bluish young arm stars
        let hiiColor = Color(red: 1.0, green: 0.48, blue: 0.60)   // pink star-forming knots
        let discColor = Color(red: 0.60, green: 0.70, blue: 0.95) // bluish diffuse haze
        let bulgeColor = Color(red: 1.0, green: 0.86, blue: 0.58) // warm central bar/bulge

        let rMax: Float = 15000
        let rInner: Float = 2400   // arms emanate from the ends of the bar
        let arms = 4
        let k: Float = 0.22        // logarithmic-spiral winding (~1.3 turns)

        // Spiral angle for a given galactocentric radius.
        func spiralAngle(_ r: Float) -> Float { Float(log(Double(r / rInner))) / k }

        var points: [BackdropPoint] = []

        // Two major arms (from the bar ends) + two minor arms, like the real galaxy.
        for armIndex in 0..<arms {
            let offset = Float(armIndex) * (.pi / 2)
            let major = (armIndex % 2 == 0)
            let starCount = major ? 2600 : 1400
            let knotCount = major ? 140 : 70
            let weight: Float = major ? 1.0 : 0.6
            for _ in 0..<starCount {
                let r = rInner + rand(0, 1) * (rMax - rInner)
                let rr = r + gaussian() * (r * 0.05 + 220)
                let angle = spiralAngle(r) + offset + gaussian() * 0.09
                let h = gaussian() * (120 + r * 0.010)
                let bright = max(0.07, 0.40 - 0.26 * (r / rMax)) * weight
                points.append(BackdropPoint(
                    position: place(cos(angle) * rr, sin(angle) * rr, h),
                    baseOpacity: Double(bright) * Double(rand(0.5, 1)),
                    size: CGFloat(rand(0.7, 1.8)),
                    color: armColor))
            }
            // Pink HII regions studding the arms — the iconic star-forming knots.
            for _ in 0..<knotCount {
                let r = rInner + rand(0.05, 1) * (rMax - rInner)
                let angle = spiralAngle(r) + offset + gaussian() * 0.05
                let cx = cos(angle) * r, cy = sin(angle) * r
                points.append(BackdropPoint(
                    position: place(cx + gaussian() * 170, cy + gaussian() * 170, gaussian() * 110),
                    baseOpacity: Double(rand(0.25, 0.55)) * Double(weight),
                    size: CGFloat(rand(0.9, 2.0)),
                    color: hiiColor))
            }
        }

        // Diffuse disc, exponential falloff — fills between the arms with a faint haze.
        for _ in 0..<3000 {
            let r = sqrt(rand(0, 1)) * rMax
            let angle = rand(0, 2 * .pi)
            let h = gaussian() * (110 + r * 0.010)
            let bright = max(0.02, 0.11 * exp(-r / 8000))
            points.append(BackdropPoint(
                position: place(cos(angle) * r, sin(angle) * r, h),
                baseOpacity: Double(bright) * Double(rand(0.4, 1)),
                size: CGFloat(rand(0.5, 1.2)),
                color: discColor))
        }

        // Central bar + bulge — warm, bright, elongated (the Milky Way is a barred spiral).
        for _ in 0..<2600 {
            let x = gaussian() * 2700      // elongated along axisA → the bar
            let y = gaussian() * 1050
            let z = gaussian() * 650
            let d = (x * x / (2700 * 2700) + y * y / (1050 * 1050) + z * z / (650 * 650)).squareRoot()
            let opacity = min(0.8, max(0.1, 0.8 - Double(d) * 0.66))
            points.append(BackdropPoint(
                position: place(x, y, z),
                baseOpacity: opacity * Double(rand(0.6, 1)),
                size: CGFloat(rand(0.8, 1.9)),
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

/// A spring-centred vertical throttle for free-fly: drag up to fly forward, down
/// to reverse; releases back to zero. Bound value is -1…1.
private struct ThrottleControl: View {
    @Binding var throttle: Float
    private let height: CGFloat = 200
    private let knob: CGFloat = 34

    var body: some View {
        let travel = height / 2 - knob / 2
        ZStack {
            Capsule().fill(.ultraThinMaterial)
            Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            VStack {
                Image(systemName: "chevron.up").font(.caption2)
                Spacer()
                Image(systemName: "chevron.down").font(.caption2)
            }
            .foregroundStyle(.white.opacity(0.4)).padding(.vertical, 8)
            Rectangle().fill(.white.opacity(0.2)).frame(height: 1)   // zero mark

            Circle()
                .fill(throttle == 0 ? Color.white : Color.green)
                .frame(width: knob, height: knob)
                .overlay(Image(systemName: "paperplane.fill").font(.caption2).foregroundStyle(.black.opacity(0.7)))
                .offset(y: -CGFloat(throttle) * travel)
                .shadow(radius: 3)
        }
        .frame(width: 46, height: height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let center = height / 2
                    throttle = max(-1, min(1, Float((center - value.location.y) / travel)))
                }
                .onEnded { _ in withAnimation(.spring(duration: 0.3)) { throttle = 0 } }
        )
    }
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
