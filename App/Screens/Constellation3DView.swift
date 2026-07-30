import SwiftUI
import simd
import CelestialCore

/// A constellation in genuine 3D. The familiar stick figure is a trick of
/// perspective — its stars lie at wildly different distances and only *line up*
/// when seen from Earth. This view places each star at its real catalog distance
/// (HYG XYZ, in parsecs, Earth at the origin), draws the figure lines between
/// them, and lets you orbit the whole shape to watch the pattern come apart with
/// depth. The reset button flies you back to the Earth-on "front" view, where the
/// pattern snaps back into its recognisable form.
struct Constellation3DView: View {
    let figure: SkyFigure
    let store: StarCatalogStore
    /// Debug-only (snapshot harness): open pre-rotated/zoomed instead of the front
    /// view + depth-bloom intro, so screenshots land on a reproducible 3D pose.
    var debugPose: (yawOffset: Float, pitchOffset: Float, zoom: Float)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var model: Constellation3DModel?

    // Orbit camera, expressed relative to the figure's centroid. yaw/pitch give the
    // direction from the centroid to the eye; distance is how far back we sit.
    @State private var yaw: Float = 0
    @State private var pitch: Float = 0
    @State private var distance: Float = 1

    // The Earth-on "front" pose, recomputed when the model loads.
    @State private var frontYaw: Float = 0
    @State private var frontPitch: Float = 0
    @State private var frontDistance: Float = 1

    @State private var dragStartYaw: Float?
    @State private var dragStartPitch: Float?
    @State private var zoomAnchor: Float = 1
    @State private var spinning = false
    @State private var spinTask: Task<Void, Never>?
    @State private var resetTask: Task<Void, Never>?
    @State private var introTask: Task<Void, Never>?

    private let fieldOfView: Float = 0.8   // radians (~46°)

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                LinearGradient(colors: [Color(red: 0.02, green: 0.03, blue: 0.09),
                                        Color(red: 0.005, green: 0.01, blue: 0.04)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                if let model {
                    let vp = makeViewProjection(model: model,
                                                aspect: Float(size.width / max(size.height, 1)))
                    Canvas { context, _ in
                        draw(model: model, in: context, size: size, viewProjection: vp)
                    }
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
                    .simultaneousGesture(zoomGesture)
                } else {
                    ProgressView().tint(.white)
                }

                overlay(safe: .deviceSafeArea)
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .task { await build() }
        .onDisappear { spinTask?.cancel(); resetTask?.cancel(); introTask?.cancel() }
    }

    // MARK: Overlay chrome

    private func overlay(safe: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                CircleIconButton(label: "Back", systemImage: "chevron.left") { dismiss() }
                Spacer()
                CircleIconButton(label: spinning ? "Stop rotation" : "Auto-rotate",
                                 systemImage: spinning ? "pause.fill" : "rotate.3d",
                                 tint: Theme.accent, isActive: spinning) { toggleSpin() }
                CircleIconButton(label: "Front view", systemImage: "house.fill",
                                 tint: Theme.accent) { resetToFront() }
            }
            .padding(.horizontal)
            .padding(.top, safe.top + 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(figure.name)
                    .font(.system(.title2, design: .serif).weight(.bold))
                    .foregroundStyle(.white)
                Text("Real distances · Earth at the centre of the front view")
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal).padding(.top, 12)

            Spacer()

            Text("Drag to rotate — the flat pattern is a line-of-sight illusion. These stars lie at very different distances.")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.bottom, safe.bottom + 16)
        }
    }

    // MARK: Camera

    /// Reconstructs the eye direction (centroid → eye) from yaw/pitch. The equatorial
    /// Z axis is the north celestial pole, so pitch tips toward north.
    private func eyeDirection(_ yaw: Float, _ pitch: Float) -> SIMD3<Float> {
        SIMD3(cos(pitch) * cos(yaw), cos(pitch) * sin(yaw), sin(pitch))
    }

    private func makeViewProjection(model: Constellation3DModel, aspect: Float) -> simd_float4x4 {
        let eye = model.centroid + distance * eyeDirection(yaw, pitch)
        let view = lookAtSafe(eye: eye, center: model.centroid, up: SIMD3(0, 0, 1))
        let near = max(0.02, (distance - model.radius) * 0.4)
        let far = (distance + model.radius) * 4 + 10
        let proj = perspective(fovy: fieldOfView, aspect: aspect, near: near, far: far)
        return proj * view
    }

    /// Light-years for a star label: one decimal for the nearest, whole grouped
    /// numbers beyond (e.g. "8.6 ly", "548 ly", "1,344 ly").
    private func formatLightYears(_ ly: Double) -> String {
        ly < 10 ? String(format: "%.1f ly", ly) : "\(Int(ly.rounded()).formatted()) ly"
    }

    private func project(_ p: SIMD3<Float>, _ vp: simd_float4x4, _ size: CGSize) -> (CGPoint, Float)? {
        let clip = vp * SIMD4<Float>(p, 1)
        guard clip.w > 0.0001 else { return nil }
        return (CGPoint(x: Double(clip.x / clip.w * 0.5 + 0.5) * size.width,
                        y: Double(0.5 - clip.y / clip.w * 0.5) * size.height), clip.w)
    }

    // MARK: Rendering

    private func draw(model: Constellation3DModel, in context: GraphicsContext,
                      size: CGSize, viewProjection vp: simd_float4x4) {
        // Sightlines from Earth out to each figure star. They collapse to nothing at the
        // exact front view (you're looking straight down them, so the stars line up) and
        // fan out into a starburst the moment you rotate away — making "these stars only
        // line up from Earth" literal. Faded by how far you've turned from the front.
        let align = simd_dot(eyeDirection(yaw, pitch), eyeDirection(frontYaw, frontPitch))
        let offFront = max(0, 1 - Double(align))
        let rayOpacity = min(0.16, offFront * 0.42)
        if rayOpacity > 0.012, let (earth, ed) = project(.zero, vp, size), ed > 0 {
            var rays = Path()
            for s in model.figureStars {
                guard let (sp, sd) = project(s, vp, size), sd > 0 else { continue }
                rays.move(to: earth); rays.addLine(to: sp)
            }
            context.stroke(rays, with: .color(Color(red: 0.45, green: 0.72, blue: 1).opacity(rayOpacity)),
                           style: StrokeStyle(lineWidth: 0.8))
        }

        // Figure lines, behind the stars: glow then a crisp core.
        var linePath = Path()
        for seg in model.segments {
            guard let (a, _) = project(seg.0, vp, size), let (b, _) = project(seg.1, vp, size) else { continue }
            linePath.move(to: a); linePath.addLine(to: b)
        }
        context.stroke(linePath, with: .color(Theme.accent.opacity(0.22)),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        context.stroke(linePath, with: .color(Theme.accent.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))

        // Stars, sized by magnitude and scaled a little by depth so nearer ones swell —
        // the cue that sells the 3D once you start to rotate.
        var glow = Path()
        for star in model.stars {
            guard let (p, depth) = project(star.position, vp, size) else { continue }
            if p.x < -20 || p.x > size.width + 20 || p.y < -20 || p.y > size.height + 20 { continue }
            let base = max(1.0, 4.4 - star.magnitude * 0.5)
            let scale = min(2.4, max(0.45, distance / depth))
            let r = CGFloat(Double(base) * Double(scale))
            if star.magnitude < 3.2 {
                let g = r * 2.6
                glow.addEllipse(in: CGRect(x: p.x - g, y: p.y - g, width: g * 2, height: g * 2))
            }
            context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(star.color))
        }
        context.fill(glow, with: .color(.white.opacity(0.10)))

        // Brightest named stars get a two-line label — name plus its real distance, so
        // the depth the rotation reveals has hard numbers attached (Betelgeuse ~548 ly,
        // Rigel ~860 ly…). De-cluttered by simple rect testing.
        var labelRects: [CGRect] = []
        for star in model.stars where star.label != nil {
            guard let (p, _) = project(star.position, vp, size) else { continue }
            let text = Text(star.label!).font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                + Text("\n" + formatLightYears(star.distanceLightYears))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.accent.opacity(0.75))
            let resolved = context.resolve(text)
            let m = resolved.measure(in: CGSize(width: 150, height: 40))
            let rect = CGRect(x: p.x + 7, y: p.y - 7 - m.height, width: m.width, height: m.height)
            guard rect.minX > 2, rect.maxX < size.width - 2, rect.minY > 2, rect.maxY < size.height - 2,
                  !labelRects.contains(where: { $0.intersects(rect) }) else { continue }
            labelRects.append(rect.insetBy(dx: -4, dy: -4))
            context.draw(resolved, at: CGPoint(x: p.x + 7, y: p.y - 7), anchor: .bottomLeading)
        }

        // Earth at the origin — the vantage the flat pattern is drawn from. Showing it
        // makes the line-of-sight idea concrete as you rotate away from the front.
        if let (e, depth) = project(.zero, vp, size), depth > 0,
           e.x > -40, e.x < size.width + 40, e.y > -40, e.y < size.height + 40 {
            context.fill(Path(ellipseIn: CGRect(x: e.x - 9, y: e.y - 9, width: 18, height: 18)),
                         with: .color(Color(red: 0.4, green: 0.7, blue: 1).opacity(0.25)))
            context.fill(Path(ellipseIn: CGRect(x: e.x - 3.5, y: e.y - 3.5, width: 7, height: 7)),
                         with: .color(Color(red: 0.45, green: 0.75, blue: 1)))
            context.draw(Text("Earth").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(red: 0.6, green: 0.82, blue: 1).opacity(0.9)),
                         at: CGPoint(x: e.x, y: e.y + 16))
        }
    }

    // MARK: Build

    private func build() async {
        guard model == nil, let catalog = store.catalog else { return }
        let figure = self.figure
        // A full-catalog scan with per-star trig plus vertex snapping — run it off
        // the main actor so the cover's presentation animation isn't frozen (the
        // ProgressView placeholder never got a frame before).
        let built = await Task.detached(priority: .userInitiated) {
            Constellation3DModel.build(figure: figure, catalog: catalog)
        }.value
        guard !built.stars.isEmpty else { model = built; return }

        // Front pose: look from Earth (origin) toward the figure, i.e. the eye sits on
        // the Earth side of the centroid. Frame so the figure fills the view.
        let toEye = simd_normalize(-built.centroid)   // centroid → Earth direction
        frontPitch = asin(max(-0.9995, min(0.9995, toEye.z)))
        frontYaw = atan2(toEye.y, toEye.x)
        // A gentle distance (~4× the figure's radius) keeps the front view close to the
        // near-orthographic shape you'd recognise from Earth, with margin for labels;
        // the depth still reveals itself the moment you start to rotate.
        frontDistance = max(built.radius / tan(fieldOfView * 0.31), built.radius * 1.2)
        yaw = frontYaw; pitch = frontPitch; distance = frontDistance
        zoomAnchor = frontDistance
        model = built
        if let pose = debugPose {
            yaw = frontYaw + pose.yawOffset
            pitch = max(-1.5699, min(1.5699, frontPitch + pose.pitchOffset))
            distance = frontDistance * pose.zoom
            zoomAnchor = distance
        } else {
            playDepthBloom()
        }
    }

    /// A one-shot "here's the depth" gesture on open: gently arcs the camera off the
    /// front view and eases it back, so the flat pattern visibly swells into 3D and
    /// settles — a hint that there's something to drag, before the user touches it.
    private func playDepthBloom() {
        introTask?.cancel()
        introTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))   // let the front view register first
            guard !Task.isCancelled else { return }
            let start = Date()
            let duration = 2.7
            let yawAmp: Float = 0.5, pitchAmp: Float = 0.17
            while !Task.isCancelled {
                let raw = min(1, Date().timeIntervalSince(start) / duration)
                let s = Float(sin(raw * .pi))            // 0 → 1 → 0, out and back
                yaw = frontYaw + yawAmp * s
                pitch = max(-1.5699, min(1.5699, frontPitch + pitchAmp * s))
                if raw >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            if !Task.isCancelled { yaw = frontYaw; pitch = frontPitch }
        }
    }

    // MARK: Interaction

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                stopSpin(); resetTask?.cancel(); introTask?.cancel()
                let sy = dragStartYaw ?? yaw
                let sp = dragStartPitch ?? pitch
                if dragStartYaw == nil { dragStartYaw = sy; dragStartPitch = sp }
                yaw = sy - Float(value.translation.width) * 0.006
                pitch = max(-1.5699, min(1.5699, sp + Float(value.translation.height) * 0.006))
            }
            .onEnded { _ in dragStartYaw = nil; dragStartPitch = nil }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                resetTask?.cancel(); introTask?.cancel()
                let r = model?.radius ?? 1
                distance = min(r * 14, max(r * 0.4, zoomAnchor / Float(value.magnification)))
            }
            .onEnded { _ in zoomAnchor = distance }
    }

    private func toggleSpin() {
        if spinning { stopSpin() } else { startSpin() }
    }

    private func startSpin() {
        spinning = true
        resetTask?.cancel()
        introTask?.cancel()
        spinTask?.cancel()
        spinTask = Task { @MainActor in
            var last = Date()
            while !Task.isCancelled {
                let now = Date()
                let dt = Float(min(0.05, now.timeIntervalSince(last)))
                last = now
                yaw += dt * 0.45
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func stopSpin() {
        guard spinning else { return }
        spinning = false
        spinTask?.cancel()
    }

    /// Eases the camera back to the Earth-on front view.
    private func resetToFront() {
        stopSpin()
        introTask?.cancel()
        resetTask?.cancel()
        let startYaw = yaw, startPitch = pitch, startDistance = distance
        var dYaw = frontYaw - startYaw
        while dYaw > .pi { dYaw -= 2 * .pi }
        while dYaw < -.pi { dYaw += 2 * .pi }
        resetTask = Task { @MainActor in
            let start = Date()
            let duration = 0.7
            while !Task.isCancelled {
                let raw = Float(min(1, Date().timeIntervalSince(start) / duration))
                let e = raw * raw * (3 - 2 * raw)
                yaw = startYaw + dYaw * e
                pitch = startPitch + (frontPitch - startPitch) * e
                distance = startDistance + (frontDistance - startDistance) * e
                zoomAnchor = distance
                if raw >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }
}

// MARK: - Model

/// A drawable star in the 3D figure: its real position (parsecs, equatorial, Earth
/// at the origin), brightness, colour and optional name.
struct Constellation3DStar: Identifiable {
    let id: Int
    let position: SIMD3<Float>
    let magnitude: Double
    let color: Color
    let label: String?
    let distanceLightYears: Double
}

/// Resolves a sky figure into real 3D geometry: the catalog stars in its patch of
/// sky placed at their true distances, plus the figure's lines snapped onto those
/// stars. Built once when the 3D view opens.
struct Constellation3DModel {
    let stars: [Constellation3DStar]
    let segments: [(SIMD3<Float>, SIMD3<Float>)]
    /// The unique stars the figure lines actually connect — the targets for the
    /// Earth sightlines (a far smaller, cleaner set than every field star).
    let figureStars: [SIMD3<Float>]
    let centroid: SIMD3<Float>
    let radius: Float

    static func build(figure: SkyFigure, catalog: StarCatalog) -> Constellation3DModel {
        let region = SkyRegion(polylines: figure.polylines)

        // Candidate stars: everything in the patch with a known distance. We keep a
        // generous magnitude limit so figure vertices can snap onto their true star
        // even when it's a touch fainter than naked-eye.
        struct Cand { let pos: SIMD3<Float>; let unit: SIMD3<Float>; let mag: Double; let star: Star }
        var candidates: [Cand] = []
        for star in catalog.stars {
            guard star.apparentMagnitude <= 7.5, region.contains(star.equatorial),
                  let parsecs = star.distanceParsecs, parsecs > 0 else { continue }
            let pos = position(of: star, parsecs: parsecs)
            candidates.append(Cand(pos: pos, unit: simd_normalize(pos), mag: star.apparentMagnitude, star: star))
        }
        guard !candidates.isEmpty else {
            return Constellation3DModel(stars: [], segments: [], figureStars: [],
                                        centroid: SIMD3(0, 0, 1), radius: 1)
        }

        // Snap every figure vertex onto the nearest candidate star (by angle), so the
        // lines connect the rendered star dots exactly. A vertex with no close star
        // falls back to its sky direction at the median figure distance.
        let medianDistance = median(candidates.map { simd_length($0.pos) })
        let cosTol = cos(2.0 * .pi / 180)
        func resolve(_ p: SIMD2<Double>) -> SIMD3<Float> {
            let u = equatorialUnit(p.x, p.y)
            var best = -2.0; var bestPos = u * Float(medianDistance)
            for c in candidates {
                let d = Double(simd_dot(u, c.unit))
                if d > best { best = d; bestPos = c.pos }
            }
            return best >= cosTol ? bestPos : u * Float(medianDistance)
        }

        var segments: [(SIMD3<Float>, SIMD3<Float>)] = []
        var figureStars: [SIMD3<Float>] = []
        func note(_ p: SIMD3<Float>) {
            if !figureStars.contains(where: { simd_distance($0, p) < 0.01 }) { figureStars.append(p) }
        }
        for line in figure.polylines where line.count >= 2 {
            var prev = resolve(line[0]); note(prev)
            for i in 1..<line.count {
                let cur = resolve(line[i]); note(cur)
                segments.append((prev, cur))
                prev = cur
            }
        }

        // Display stars: naked-eye members of the patch, brightest first, capped.
        let display = candidates.filter { $0.mag <= 6.5 }
            .sorted { $0.mag < $1.mag }
            .prefix(450)
        let stars = display.map { c in
            Constellation3DStar(
                id: c.star.id,
                position: c.pos,
                magnitude: c.mag,
                color: StarColor.from(colorIndex: c.star.colorIndex),
                label: c.mag <= 3.0 ? (c.star.properName ?? c.star.bayerFlamsteed) : nil,
                distanceLightYears: Double(simd_length(c.pos)) * Astrophysics.lightYearsPerParsec)
        }

        // Centre and frame on the figure itself (its line vertices) so rotation orbits
        // the shape, not stray faint field stars.
        let pts = segments.flatMap { [$0.0, $0.1] }
        let basis = pts.isEmpty ? stars.map(\.position) : pts
        var sum = SIMD3<Float>(repeating: 0)
        for p in basis { sum += p }
        let centroid = sum / Float(max(1, basis.count))
        var radius: Float = 1
        for p in basis { radius = max(radius, simd_length(p - centroid)) }

        return Constellation3DModel(stars: stars, segments: segments, figureStars: figureStars,
                                    centroid: centroid, radius: radius)
    }

    private static func position(of star: Star, parsecs: Double) -> SIMD3<Float> {
        if let p = star.position { return SIMD3(Float(p.x), Float(p.y), Float(p.z)) }
        let ra = Float(star.equatorial.rightAscension.radians)
        let dec = Float(star.equatorial.declination.radians)
        let d = Float(parsecs)
        return SIMD3(d * cos(dec) * cos(ra), d * cos(dec) * sin(ra), d * sin(dec))
    }
}

private func equatorialUnit(_ raDeg: Double, _ decDeg: Double) -> SIMD3<Float> {
    let ra = Float(raDeg * .pi / 180), dec = Float(decDeg * .pi / 180)
    return SIMD3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))
}

private func median(_ values: [Float]) -> Double {
    guard !values.isEmpty else { return 1 }
    let s = values.sorted()
    return Double(s[s.count / 2])
}

// MARK: - 3D matrix helpers (file-local; mirror the Galaxy Map's camera math)

/// `lookAt` that survives a view direction parallel to `up` (e.g. a constellation
/// sitting on the celestial pole) by falling back to an alternate up vector.
private func lookAtSafe(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
    let f = simd_normalize(center - eye)
    var u = up
    if abs(simd_dot(f, u)) > 0.999 { u = SIMD3(0, 1, 0) }
    if abs(simd_dot(f, u)) > 0.999 { u = SIMD3(1, 0, 0) }
    let s = simd_normalize(simd_cross(f, u))
    let uu = simd_cross(s, f)
    return simd_float4x4(columns: (
        SIMD4(s.x, uu.x, -f.x, 0),
        SIMD4(s.y, uu.y, -f.y, 0),
        SIMD4(s.z, uu.z, -f.z, 0),
        SIMD4(-simd_dot(s, eye), -simd_dot(uu, eye), simd_dot(f, eye), 1)
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
