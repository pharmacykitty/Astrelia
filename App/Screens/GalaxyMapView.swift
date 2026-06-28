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
    private let flySpeed: Float = 1540   // parsecs/second at full throttle

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
        let focal = Double(1 / tan(fieldOfView / 2))
        let halfH = Double(size.height) * 0.5
        let maxDim = Double(max(size.width, size.height))

        // Broad galactic glow: a soft continuous haze around the disc/core so the
        // Milky Way reads as luminous structure, not just discrete points. Cheap
        // (a couple of radial gradients), drawn under the point field.
        if let (cp, cdepth) = project(Galactic.centerPosition, viewProjection, size), cdepth > 0 {
            let pxPerPc = halfH * focal / Double(cdepth)
            let discR = CGFloat(min(maxDim * 1.8, 15000 * pxPerPc))
            let coreR = CGFloat(min(maxDim, 3200 * pxPerPc))
            func rect(_ rad: CGFloat) -> CGRect { CGRect(x: cp.x - rad, y: cp.y - rad, width: rad * 2, height: rad * 2) }
            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                if discR > 6 {
                    layer.fill(Path(ellipseIn: rect(discR)),
                               with: .radialGradient(Gradient(colors: [Color(red: 0.45, green: 0.55, blue: 0.85).opacity(0.12), .clear]),
                                                     center: cp, startRadius: 0, endRadius: discR))
                }
                if coreR > 4 {
                    layer.fill(Path(ellipseIn: rect(coreR)),
                               with: .radialGradient(Gradient(colors: [Color(red: 1.0, green: 0.9, blue: 0.7).opacity(0.35), .clear]),
                                                     center: cp, startRadius: 0, endRadius: coreR))
                }
            }
        }

        // Stylized Milky Way: batched into a blurred, additive layer. Points are
        // grouped by colour and a coarse opacity level, so we issue ~16 fills
        // instead of thousands. Off-screen and sub-pixel points are culled.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 3.0))
            layer.blendMode = .plusLighter
            var paths = Array(repeating: Array(repeating: Path(), count: backdropOpacityLevels.count),
                              count: backdropPalette.count)
            for point in backdrop {
                guard let (p, depth) = project(point.position, viewProjection, size) else { continue }
                if p.x < -4 || p.x > size.width + 4 || p.y < -4 || p.y > size.height + 4 { continue }
                let r = point.size * CGFloat(min(3.2, max(0.8, Double(900 / depth))))
                if r < 0.45 { continue }
                let o = point.baseOpacity
                let lvl = o < 0.2 ? 0 : (o < 0.39 ? 1 : (o < 0.62 ? 2 : 3))
                paths[point.colorBucket][lvl].addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
            for c in backdropPalette.indices {
                for l in backdropOpacityLevels.indices {
                    layer.fill(paths[c][l], with: .color(backdropPalette[c].opacity(backdropOpacityLevels[l])))
                }
            }
        }

        // Real stars: one path per colour bucket → 6 fills total, with off-screen +
        // sub-pixel culling and an overall cap for level-of-detail.
        var starPaths = Array(repeating: Path(), count: starPalette.count)
        var glowPath = Path()
        var drawn = 0
        for star in stars {
            guard let (p, depth) = project(star.position, viewProjection, size) else { continue }
            if p.x < -3 || p.x > size.width + 3 || p.y < -3 || p.y > size.height + 3 { continue }
            let r = star.baseSize * CGFloat(min(3.0, max(0.4, 150 / depth)))
            if r < 0.5 { continue }
            if star.magnitude < 1.5 {
                let g = r * 3
                glowPath.addEllipse(in: CGRect(x: p.x - g, y: p.y - g, width: g * 2, height: g * 2))
            }
            starPaths[star.colorBucket].addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            drawn += 1
            if drawn >= 14000 { break }
        }
        context.fill(glowPath, with: .color(.white.opacity(0.12)))
        for i in starPalette.indices {
            context.fill(starPaths[i], with: .color(starPalette[i].opacity(0.95)))
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
                drawLandmark(context, landmark, at: p, radius: r)
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
    private func drawLandmark(_ context: GraphicsContext, _ landmark: Landmark, at p: CGPoint, radius r: CGFloat) {
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
            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                layer.fill(Path(ellipseIn: rect(p, r)),
                           with: .radialGradient(Gradient(colors: [color.opacity(0.40), color.opacity(0.0)]),
                                                 center: p, startRadius: 0, endRadius: r))
                if landmark.type == .planetaryNebula {
                    layer.stroke(Path(ellipseIn: rect(p, r * 0.55)), with: .color(color.opacity(0.6)),
                                 lineWidth: max(1.5, r * 0.18))
                    layer.fill(Path(ellipseIn: rect(p, max(1.5, r * 0.08))), with: .color(.white))
                } else {
                    let knots = Int(min(14, max(4, r / 12)))
                    for _ in 0..<knots {
                        let ang = rnd(0, 2 * .pi), rad = rnd(0, Double(r) * 0.65)
                        let kp = CGPoint(x: p.x + CGFloat(cos(ang) * rad), y: p.y + CGFloat(sin(ang) * rad))
                        let kr = r * CGFloat(rnd(0.06, 0.20))
                        let kc = landmark.type == .supernovaRemnant ? color : Color(red: 1.0, green: 0.62, blue: 0.72)
                        layer.fill(Path(ellipseIn: rect(kp, kr)),
                                   with: .radialGradient(Gradient(colors: [kc.opacity(0.55), .clear]),
                                                         center: kp, startRadius: 0, endRadius: kr))
                    }
                    layer.fill(Path(ellipseIn: rect(p, max(1.2, r * 0.04))), with: .color(.white.opacity(0.7)))
                }
            }

        case .openCluster, .globularCluster:
            let globular = landmark.type == .globularCluster
            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                if globular {
                    layer.fill(Path(ellipseIn: rect(p, r * 0.6)),
                               with: .radialGradient(Gradient(colors: [color.opacity(0.35), .clear]),
                                                     center: p, startRadius: 0, endRadius: r * 0.6))
                }
                let n = globular ? 160 : 50
                for _ in 0..<n {
                    let rad: Double = globular ? abs(gauss()) * Double(r) * 0.42 : rnd(0, Double(r))
                    let ang = rnd(0, 2 * .pi)
                    let sp = CGPoint(x: p.x + CGFloat(cos(ang) * rad), y: p.y + CGFloat(sin(ang) * rad))
                    let dr = CGFloat(rnd(0.6, 1.7))
                    layer.fill(Path(ellipseIn: rect(sp, dr)), with: .color(.white.opacity(0.9)))
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

    private func overlay(size: CGSize, viewProjection: simd_float4x4) -> some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    CircleIconButton(label: "Back", systemImage: "chevron.left") { dismiss() }
                    Text("\(stars.count) stars")
                        .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    CircleIconButton(label: "Centre on the Sun", systemImage: "sun.max.fill") {
                        exitFlyMode(); animateCamera(to: .zero, distance: 220)
                    }
                    CircleIconButton(label: "Galaxy overview", systemImage: "hurricane") {
                        exitFlyMode(); flyToGalaxy()
                    }
                    CircleIconButton(label: flyMode ? "Exit free flight" : "Free flight",
                                     systemImage: flyMode ? "airplane.circle.fill" : "airplane",
                                     tint: .green, isActive: flyMode) {
                        flyMode ? exitFlyMode() : enterFlyMode()
                    }
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
            Button(action: fly) {
                Label("Fly here", systemImage: "paperplane.fill").font(.subheadline)
            }
            .buttonStyle(.borderedProminent).tint(tint == .white ? .blue : tint)
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: Theme.cardRadius))
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
            let starCount = major ? 1500 : 800
            let knotCount = major ? 90 : 45
            let weight: Float = major ? 1.0 : 0.6
            for _ in 0..<starCount {
                let r = rInner + rand(0, 1) * (rMax - rInner)
                let rr = r + gaussian() * (r * 0.05 + 220)
                let angle = spiralAngle(r) + offset + gaussian() * 0.09
                let h = gaussian() * (120 + r * 0.010)
                let bright = max(0.09, 0.52 - 0.30 * (r / rMax)) * weight
                points.append(BackdropPoint(
                    position: place(cos(angle) * rr, sin(angle) * rr, h),
                    colorBucket: armBucket,
                    baseOpacity: Double(bright) * Double(rand(0.5, 1)),
                    size: CGFloat(rand(0.8, 2.0))))
            }
            // Pink HII regions studding the arms — the iconic star-forming knots.
            for _ in 0..<knotCount {
                let r = rInner + rand(0.05, 1) * (rMax - rInner)
                let angle = spiralAngle(r) + offset + gaussian() * 0.05
                let cx = cos(angle) * r, cy = sin(angle) * r
                points.append(BackdropPoint(
                    position: place(cx + gaussian() * 170, cy + gaussian() * 170, gaussian() * 110),
                    colorBucket: hiiBucket,
                    baseOpacity: Double(rand(0.3, 0.65)) * Double(weight),
                    size: CGFloat(rand(1.0, 2.2))))
            }
        }

        // Diffuse disc, exponential falloff — fills between the arms with a faint haze.
        for _ in 0..<1800 {
            let r = sqrt(rand(0, 1)) * rMax
            let angle = rand(0, 2 * .pi)
            let h = gaussian() * (110 + r * 0.010)
            let bright = max(0.03, 0.16 * exp(-r / 8000))
            points.append(BackdropPoint(
                position: place(cos(angle) * r, sin(angle) * r, h),
                colorBucket: discBucket,
                baseOpacity: Double(bright) * Double(rand(0.4, 1)),
                size: CGFloat(rand(0.6, 1.4))))
        }

        // Central bar + bulge — warm, bright, elongated (the Milky Way is a barred spiral).
        for _ in 0..<1700 {
            let x = gaussian() * 2700      // elongated along axisA → the bar
            let y = gaussian() * 1050
            let z = gaussian() * 650
            let d = (x * x / (2700 * 2700) + y * y / (1050 * 1050) + z * z / (650 * 650)).squareRoot()
            let opacity = min(0.85, max(0.12, 0.85 - Double(d) * 0.66))
            points.append(BackdropPoint(
                position: place(x, y, z),
                colorBucket: bulgeBucket,
                baseOpacity: opacity * Double(rand(0.6, 1)),
                size: CGFloat(rand(0.9, 2.1))))
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
    Color(red: 0.72, green: 0.82, blue: 1.0),    // 0 arm
    Color(red: 1.0, green: 0.48, blue: 0.60),    // 1 HII knot
    Color(red: 0.60, green: 0.70, blue: 0.95),   // 2 disc haze
    Color(red: 1.0, green: 0.85, blue: 0.55),    // 3 bar/bulge
]

private let backdropOpacityLevels: [Double] = [0.12, 0.28, 0.5, 0.75]

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
