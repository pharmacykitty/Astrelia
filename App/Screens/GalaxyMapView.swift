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
    @State private var octree: PointOctree?             // spatial index over star positions (frustum cull + picking)
    @State private var flightTask: Task<Void, Never>?

    // Metal renderer (Phase 7) — the only renderer. The scene is rebuilt (and
    // `version` bumped) whenever the catalogue or art changes.
    @State private var scene = GalaxyScene()
    @State private var sceneVersion = 0

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

                // Gestures live on the render layer (below the overlay) so taps on
                // overlay buttons interact with the button, not the stars behind it.
                GalaxyMetalView(scene: scene, sceneVersion: sceneVersion,
                                camera: makeCamera(aspect: Float(size.width / max(size.height, 1)), size: size))
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
                    .simultaneousGesture(zoomGesture)
                    .simultaneousGesture(tapGesture(size: size, viewProjection: viewProjection, hostHIPs: hostHIPs))

                // Metal draws the bodies; labels, the Sun caption and the selection
                // ring stay vector (crisp text) in this lightweight Canvas on top.
                metalAnnotations(size: size, viewProjection: viewProjection)

                overlay(size: size, viewProjection: viewProjection, safe: .deviceSafeArea)
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: store.catalog?.count ?? 0) {
            buildStars(); buildBackdrop(); buildScene(); applyInitialFocusIfNeeded()
        }
        .onChange(of: exo.hostHIPs.count) { buildScene() }
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


    /// Vector annotations for the Metal path — labels, the Sun caption and the
    /// selection ring (crisp text the GPU sprite layer doesn't draw). Projected on the
    /// CPU with the same world view-projection the picker uses.
    private func metalAnnotations(size: CGSize, viewProjection: simd_float4x4) -> some View {
        Canvas { context, _ in
            let focal = Double(1 / tan(fieldOfView / 2))
            if let (sp, _) = project(.zero, viewProjection, size) {
                context.draw(Text("Sol").font(.system(size: 10, weight: .semibold)).foregroundStyle(.orange),
                             at: CGPoint(x: sp.x, y: sp.y + 14))
            }
            var labelRects: [CGRect] = []
            for lm in Landmarks.all {
                guard let (p, depth) = project(lm.positionParsecs, viewProjection, size), depth > 0 else { continue }
                let screenRadius = lm.radiusParsecs * (Double(size.height) * 0.5) * focal / Double(depth)
                let r = CGFloat(max(2.0, min(screenRadius, Double(max(size.width, size.height)) * 1.5)))
                if p.x < -r - 30 || p.x > size.width + r + 30 || p.y < -r - 30 || p.y > size.height + r + 30 { continue }
                let labelY = p.y + CGFloat(min(Double(r) + 8, 70))
                let text = Text(lm.name).font(.system(size: 9, weight: .medium)).foregroundStyle(lm.type.color.opacity(0.95))
                let resolved = context.resolve(text)
                let m = resolved.measure(in: CGSize(width: 160, height: 40))
                let rect = CGRect(x: p.x - m.width / 2, y: labelY - m.height / 2, width: m.width, height: m.height)
                if rect.minX > 2, rect.maxX < size.width - 2, rect.minY > 2, rect.maxY < size.height - 2,
                   !labelRects.contains(where: { $0.intersects(rect) }) {
                    labelRects.append(rect.insetBy(dx: -3, dy: -3))
                    context.draw(resolved, at: CGPoint(x: p.x, y: labelY))
                }
            }
            if let selection, let (point, _) = project(selection.position, viewProjection, size) {
                context.stroke(Path(ellipseIn: CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24)),
                               with: .color(.white), lineWidth: 1.5)
            }
        }
        .allowsHitTesting(false)
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
                showMilkyWay.toggle(); buildScene()
            }
            optionRow("Planet hosts only", "globe.americas.fill", tint: teal, toggle: true, isOn: hostsOnly) {
                hostsOnly.toggle(); buildScene()
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

    /// Camera for the Metal renderer: the same view as `makeViewProjection`, but built
    /// camera-relative (eye at the origin) so positions fed to the GPU stay small —
    /// float precision over the galaxy's huge scale range.
    private func makeCamera(aspect: Float, size: CGSize) -> GalaxyCamera {
        let dir = lookDirection
        let cameraEye: SIMD3<Float>
        let center: SIMD3<Float>
        if flyMode {
            cameraEye = eye
            center = eye - dir
        } else {
            cameraEye = target + distance * dir
            center = target
        }
        let view = lookAt(eye: .zero, center: center - cameraEye, up: SIMD3(0, 1, 0))
        let projection = perspective(fovy: fieldOfView, aspect: aspect, near: 0.05, far: 200000)
        let focal = 1 / tan(fieldOfView / 2)
        return GalaxyCamera(viewProj: projection * view, eye: cameraEye,
                            halfHeightFocal: Float(size.height / 2) * focal, viewSize: size)
    }

    // MARK: Metal scene

    private func rgba(_ color: Color) -> SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), Float(a))
    }

    /// Translates the catalogue + procedural art into GPU sprite instances (world
    /// space, built once per data/art change). Mirrors the Canvas layers: hard-disc
    /// stars with glow on the brightest, and the Milky Way as crisp + bloom + dust.
    /// (Landmarks/nebulae/labels are ported in a later milestone.)
    private func buildScene() {
        guard !stars.isEmpty else { return }
        let starCols = starPalette.map(rgba)
        let backCols = backdropPalette.map(rgba)
        let dust = rgba(backdropDustColor)

        let hostHIPs = exo.hostHIPs

        var additive: [GalaxySprite] = []          // occludee light (stars, Milky Way) — tests depth
        additive.reserveCapacity(stars.count + (showMilkyWay ? backdrop.count * 2 : 0) + 4000)
        var landmarkLight: [GalaxySprite] = []      // landmark/nebula light — never depth-tested
        var occluder: [GalaxySprite] = []           // invisible depth-only caps (dense, opaque cores)
        var overlay: [GalaxySprite] = []

        for s in stars {
            if hostsOnly && !(s.hip.map { hostHIPs.contains($0) } ?? false) { continue }
            let base = Float(s.baseSize)
            let c = starCols[s.colorBucket]
            // Brightness-driven alpha (apparent magnitude). With 100k+ additive sprites
            // a constant alpha saturates to white wherever the cloud is dense (through
            // the middle of the local bubble); fading the many faint stars keeps dense
            // regions a soft glow while the bright stars still read as distinct points.
            let mag = Float(s.magnitude)
            let alpha = max(0.07, min(0.85, 0.85 - 0.12 * (mag - 1.0)))
            additive.append(GalaxySprite(position: s.position, radius: 150 * base,
                                         color: SIMD4(c.x, c.y, c.z, alpha),
                                         minPixel: 0.4 * base, maxPixel: 3.0 * base, softness: 0, mode: 1))
            if s.magnitude < 1.5 {   // soft white glow on the brightest, like the Canvas path
                additive.append(GalaxySprite(position: s.position, radius: 450 * base,
                                             color: SIMD4(1, 1, 1, 0.12),
                                             minPixel: 1.2 * base, maxPixel: 9.0 * base, softness: 1, mode: 1))
            }
        }

        // The Sun, at the origin.
        additive.append(GalaxySprite(position: .zero, radius: 320, color: SIMD4(1.0, 0.6, 0.1, 1),
                                     minPixel: 3, maxPixel: 7, softness: 0, mode: 1))
        additive.append(GalaxySprite(position: .zero, radius: 950, color: SIMD4(1.0, 0.6, 0.1, 0.28),
                                     minPixel: 7, maxPixel: 20, softness: 1, mode: 1))

        // Landmarks (nebulae, clusters, galaxies, black holes) as world-space sprites.
        appendLandmarkSprites(&landmarkLight, &occluder, &overlay)

        if showMilkyWay {
            // A soft warm nucleus glow (modest so it doesn't wash out when flown into;
            // the dense bulge points carry most of the core's brightness).
            additive.append(GalaxySprite(position: Galactic.centerPosition, radius: 3200,
                                         color: SIMD4(1.0, 0.78, 0.45, 0.22), minPixel: 0, maxPixel: 1200, softness: 1, mode: 0))
            additive.append(GalaxySprite(position: Galactic.centerPosition, radius: 1100,
                                         color: SIMD4(1.0, 0.9, 0.7, 0.35), minPixel: 0, maxPixel: 900, softness: 1, mode: 0))
        }

        if showMilkyWay {
            for p in backdrop {
                let sz = Float(p.size), op = Float(p.baseOpacity)
                let c = backCols[p.colorBucket]
                additive.append(GalaxySprite(position: p.position, radius: 800 * sz,
                                             color: SIMD4(c.x, c.y, c.z, op),
                                             minPixel: 0.6 * sz, maxPixel: 3.4 * sz, softness: 0.25, mode: 1))
                additive.append(GalaxySprite(position: p.position, radius: 1920 * sz,    // bloom
                                             color: SIMD4(c.x, c.y, c.z, op * 0.55),
                                             minPixel: 1.5 * sz, maxPixel: 8.0 * sz, softness: 1, mode: 1))
            }
            for d in backdropDust {
                let sz = Float(d.size), op = Float(min(0.9, d.baseOpacity * 1.2))
                overlay.append(GalaxySprite(position: d.position, radius: 900 * sz,
                                            color: SIMD4(dust.x, dust.y, dust.z, op),
                                            minPixel: 0.6 * sz, maxPixel: 9.0 * sz, softness: 1, mode: 1))
            }
        }

        scene = GalaxyScene(additive: additive, landmarkLight: landmarkLight, occluder: occluder, overlay: overlay)
        sceneVersion += 1
    }

    /// Emits world-space sprite instances for every landmark — the GPU equivalent of
    /// the Canvas `drawLandmark`/`drawNebula`/… generators. Same seeded 3D structure,
    /// so each object looks identical run to run and parallaxes with the camera.
    // `additive` here receives landmark/nebula *light* (it is never depth-tested);
    // `occluder` receives invisible depth-only caps marking dense, opaque cores.
    private func appendLandmarkSprites(_ additive: inout [GalaxySprite], _ occluder: inout [GalaxySprite], _ overlay: inout [GalaxySprite]) {
        let pink = SIMD4<Float>(1.0, 0.55, 0.72, 1)
        let dustC = rgba(backdropDustColor)
        // Astrophysical emission palette for the overhauled landmark looks.
        let haAlpha = SIMD4<Float>(1.0, 0.42, 0.55, 1)   // hydrogen-alpha rose
        let haDeep  = SIMD4<Float>(0.96, 0.26, 0.40, 1)  // deeper Hα knots
        let oiii    = SIMD4<Float>(0.40, 0.93, 0.80, 1)  // doubly-ionised oxygen teal
        let reflect = SIMD4<Float>(0.45, 0.62, 1.0, 1)   // blue reflection / young stars
        let starBW  = SIMD4<Float>(0.72, 0.82, 1.0, 1)   // hot blue-white star

        for lm in Landmarks.all {
            let center = lm.positionParsecs
            let physR = Float(lm.radiusParsecs)
            // Image-baked nebulae (true shape from a real photo) take precedence over
            // the procedural generator.
            if let model = NebulaLibrary.model(for: lm.id) {
                appendBakedNebula(lm, model, center: center, physR: physR, dustC: dustC, &additive, &occluder, &overlay)
                continue
            }
            let color = rgba(lm.type.color)
            var rng = SeededGenerator(seed: lm.id.unicodeScalars.reduce(UInt64(1469598103)) { $0 &* 31 &+ UInt64($1.value) })
            func rnd(_ a: Double, _ b: Double) -> Double { Double.random(in: a...b, using: &rng) }
            func gauss() -> Double {
                let u1 = Double.random(in: 1e-6...1, using: &rng), u2 = Double.random(in: 0...1, using: &rng)
                return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
            }
            func g3() -> SIMD3<Float> { SIMD3(Float(gauss()), Float(gauss()), Float(gauss())) }
            func unit() -> SIMD3<Float> {
                let z = rnd(-1, 1), t = rnd(0, 2 * .pi), rxy = (1 - z * z).squareRoot()
                return SIMD3(Float(cos(t) * rxy), Float(sin(t) * rxy), Float(z))
            }
            let a = simd_normalize(g3() + SIMD3(0.0001, 0, 0))
            let b = simd_normalize(g3() - a * simd_dot(a, g3()))
            let (ex, ey, ez) = (a, b, simd_cross(a, b))
            let aniso = SIMD3<Float>(1, Float(rnd(0.55, 0.95)), Float(rnd(0.6, 0.95)))
            func shape(_ v: SIMD3<Float>) -> SIMD3<Float> { ex * (v.x * aniso.x) + ey * (v.y * aniso.y) + ez * (v.z * aniso.z) }

            func gas(_ pos: SIMD3<Float>, _ rad: Float, _ c: SIMD4<Float>, _ op: Double, _ soft: Float = 0.55) {
                additive.append(GalaxySprite(position: pos, radius: rad, color: SIMD4(c.x, c.y, c.z, Float(op)),
                                             minPixel: 0, maxPixel: 1400, softness: soft, mode: 0))
            }
            // An invisible depth-only "cap": writes a landmark's dense, opaque core into
            // the depth buffer so background stars behind it are occluded — adds no light
            // (colour 0). Hard disc so most of its area writes depth. Use only where the
            // object is genuinely opaque (dense nebula lobes, galaxy bulges, globular cores).
            func cap(_ pos: SIMD3<Float>, _ rad: Float) {
                occluder.append(GalaxySprite(position: pos, radius: rad, color: SIMD4(0, 0, 0, 0),
                                             minPixel: 0, maxPixel: 1400, softness: 0, mode: 0))
            }
            // A point star with an optional soft glow halo — for cluster members,
            // embedded young stars, and bright knots in the overhauled looks.
            func star(_ pos: SIMD3<Float>, _ rad: Float, _ c: SIMD4<Float>, _ op: Double, glow: Bool = false) {
                if glow {
                    additive.append(GalaxySprite(position: pos, radius: rad * 4.5, color: SIMD4(c.x, c.y, c.z, Float(op) * 0.22),
                                                 minPixel: 1, maxPixel: 16, softness: 1, mode: 0))
                }
                additive.append(GalaxySprite(position: pos, radius: rad, color: SIMD4(c.x, c.y, c.z, Float(op)),
                                             minPixel: 0.6, maxPixel: 3.6, softness: 0, mode: 0))
            }
            // A stellar colour from an age-appropriate population: old (globular/bulge,
            // redder) vs young (open cluster/arm, bluer).
            func popColor(old: Bool) -> SIMD4<Float> {
                let r = rnd(0, 1)
                if old {
                    if r < 0.16 { return starBW } else if r < 0.42 { return SIMD4(1, 1, 1, 1) }
                    else if r < 0.66 { return SIMD4(1, 0.95, 0.8, 1) } else if r < 0.84 { return SIMD4(1, 0.86, 0.6, 1) }
                    else if r < 0.94 { return SIMD4(1, 0.72, 0.45, 1) } else { return SIMD4(1, 0.56, 0.42, 1) }
                }
                if r < 0.42 { return starBW } else if r < 0.72 { return SIMD4(1, 1, 1, 1) }
                else if r < 0.9 { return SIMD4(1, 0.95, 0.8, 1) } else { return SIMD4(1, 0.86, 0.6, 1) }
            }
            func dustPuff(_ pos: SIMD3<Float>, _ rad: Float, _ op: Double) {
                overlay.append(GalaxySprite(position: pos, radius: rad, color: SIMD4(dustC.x, dustC.y, dustC.z, Float(op)),
                                            minPixel: 0, maxPixel: 1400, softness: 1, mode: 0))
            }
            func embedded(_ pos: SIMD3<Float>) {
                additive.append(GalaxySprite(position: pos, radius: physR * 0.16, color: SIMD4(1, 1, 1, 0.5),
                                             minPixel: 1, maxPixel: 10, softness: 1, mode: 0))
                additive.append(GalaxySprite(position: pos, radius: physR * 0.04, color: SIMD4(1, 1, 1, 1),
                                             minPixel: 1, maxPixel: 3.5, softness: 0, mode: 0))
            }
            func dustLane(_ dir: SIMD3<Float>, count: Int, span: Float, thickness: Float, op: ClosedRange<Double>) {
                let u = simd_normalize(shape(dir))
                for _ in 0..<count {
                    let t = Float(rnd(-1, 1)) * physR * span
                    dustPuff(center + u * t + shape(g3()) * (physR * thickness), physR * Float(rnd(0.06, 0.16)), rnd(op.lowerBound, op.upperBound))
                }
            }

            switch lm.type {
            case .planetaryNebula:
                let axis = simd_normalize(shape(unit()))
                let shellR = physR * 0.6
                // Two-colour shell: hot OIII teal inside, cooler Hα rose at the rim.
                for _ in 0..<120 {
                    let d = simd_normalize(shape(unit()))
                    let rr = shellR * Float(rnd(0.9, 1.12))
                    let edge = Double((rr / shellR - 0.9) / 0.22)            // 0 inner … 1 rim
                    gas(center + d * rr, physR * Float(rnd(0.08, 0.16)), edge > 0.55 ? haAlpha : oiii, 0.16 + (1 - edge) * 0.24, 0.9)
                }
                // Bipolar lobes (many planetaries are bipolar).
                for s in [-1.0, 1.0] {
                    let lobe = center + axis * (shellR * Float(s) * 0.85)
                    for _ in 0..<16 { gas(lobe + shape(g3()) * shellR * 0.34, physR * Float(rnd(0.1, 0.2)), oiii, 0.15, 0.9) }
                }
                // Faint extended halo (older ejected shell).
                for _ in 0..<44 { gas(center + simd_normalize(shape(unit())) * shellR * Float(rnd(1.15, 1.5)), physR * 0.1, haAlpha, 0.05, 1) }
                // Central hot white-dwarf: a blue-white point with a glow.
                star(center, physR * 0.05, SIMD4(0.82, 0.9, 1, 1), 1.0, glow: true)

            case .supernovaRemnant:
                let shellR = physR * 0.85
                // Filamentary two-colour rim: Hα rose + blue/OIII wisps.
                for _ in 0..<210 {
                    let d = simd_normalize(shape(unit()))
                    gas(center + d * shellR * Float(rnd(0.8, 1.07)), physR * Float(rnd(0.04, 0.1)), rnd(0, 1) < 0.5 ? haAlpha : reflect, rnd(0.28, 0.5), 0.7)
                }
                // Brighter knots along the rim.
                for _ in 0..<28 {
                    let d = simd_normalize(shape(unit()))
                    gas(center + d * shellR * Float(rnd(0.85, 1.03)), physR * Float(rnd(0.06, 0.12)), rnd(0, 1) < 0.5 ? oiii : haDeep, 0.5, 0.6)
                }
                // Faint interior glow + a neutron star/pulsar for the famous youngsters.
                for _ in 0..<24 { gas(center + shape(g3()) * physR * 0.45, physR * Float(rnd(0.25, 0.5)), reflect, 0.05) }
                if lm.id == "m1" || lm.id == "vela" || lm.id == "casa" { star(center, physR * 0.05, SIMD4(0.72, 0.85, 1, 1), 1.0, glow: true) }

            case .emissionNebula:
                if lm.id == "horsehead" {
                    for _ in 0..<46 {
                        let off = (ex * Float(rnd(-1, 1)) + ey * Float(rnd(-1, 1)) + ez * Float(gauss()) * 0.3) * physR
                        gas(center + off + ex * physR * 0.5, physR * Float(rnd(0.3, 0.55)), rnd(0, 1) < 0.6 ? color : pink, rnd(0.12, 0.24))
                    }
                    for _ in 0..<240 {
                        let h = Float(rnd(-0.9, 0.55)), bulge: Float = (rnd(0, 1) > 0 && h > 0.35) ? 0.42 : 0.16
                        let pos = center - ex * physR * 0.35 + ey * (h * physR) + ex * (Float(rnd(-1, 1)) * physR * bulge) + ez * Float(gauss()) * physR * 0.12
                        dustPuff(pos, physR * Float(rnd(0.07, 0.16)), rnd(0.4, 0.8))
                    }
                    for _ in 0..<10 {
                        let h = Float(rnd(-0.6, 0.6))
                        gas(center - ex * physR * 0.05 + ey * (h * physR), physR * Float(rnd(0.05, 0.1)), pink, rnd(0.3, 0.5))
                    }
                } else {
                    // Layered cloud: warm Hα body, OIII-energised cores, blue reflection.
                    var lobes: [(SIMD3<Float>, Float)] = []
                    for _ in 0..<7 { lobes.append((shape(g3()) * (physR * 0.45), Float(rnd(0.4, 0.85)))) }
                    for _ in 0..<150 {
                        let (lc, ls) = lobes[Int(rnd(0, 6.999))]
                        let pos = center + lc + shape(g3()) * (physR * ls * 0.5)
                        let outer = Double(simd_length(lc) / max(physR, 0.001))
                        let r = rnd(0, 1)
                        let c = r < 0.12 ? oiii : (r < 0.12 + outer * 0.4 ? reflect : (r < 0.9 ? haAlpha : haDeep))
                        gas(pos, physR * Float(rnd(0.18, 0.42)) * ls, c, rnd(0.07, 0.16))
                    }
                    for _ in 0..<16 { gas(center + shape(g3()) * (physR * 0.4), physR * Float(rnd(0.05, 0.12)), haDeep, rnd(0.42, 0.6), 0.7) }
                    // Embedded young cluster lighting the cloud from within.
                    let cl = center + shape(g3()) * physR * 0.3
                    for _ in 0..<12 { star(cl + shape(g3()) * physR * 0.18, physR * 0.02, starBW, rnd(0.5, 0.9), glow: rnd(0, 1) < 0.3) }
                    for _ in 0..<6 { embedded(center + shape(g3()) * (physR * 0.5)) }
                    // Depth caps over the dense lobes so background stars are occluded.
                    for (lc, ls) in lobes { cap(center + lc, physR * 0.2 * ls) }
                    switch lm.id {
                    case "m20":
                        for i in 0..<3 { let ang = Double(i) * (.pi / 3) + 0.2; dustLane(SIMD3(Float(cos(ang)), Float(sin(ang)), 0), count: 70, span: 0.95, thickness: 0.05, op: 0.35...0.75) }
                    case "m16":
                        dustLane(SIMD3(0.2, 1, 0), count: 80, span: 0.7, thickness: 0.08, op: 0.3...0.65)
                        dustLane(SIMD3(-0.5, 0.8, 0.2), count: 55, span: 0.55, thickness: 0.07, op: 0.25...0.55)
                    case "m8", "carina", "rosette":
                        dustLane(SIMD3(Float(rnd(-1, 1)), 1, 0), count: 60, span: 0.9, thickness: 0.09, op: 0.2...0.45)
                    default: break
                    }
                }

            case .openCluster, .globularCluster:
                let globular = lm.type == .globularCluster
                if globular {
                    gas(center, physR * 0.7, SIMD4(1, 0.92, 0.7, 1), 0.20, 1)     // warm layered core glow
                    gas(center, physR * 0.34, SIMD4(1, 0.95, 0.82, 1), 0.28, 1)
                    cap(center, physR * 0.4)                                       // dense core occludes background
                }
                let n = globular ? 260 : 70
                for _ in 0..<n {
                    let dir = unit()
                    let frac = globular ? min(1, abs(gauss()) * 0.4) : pow(rnd(0, 1), 1.0 / 3.0)
                    star(center + dir * (physR * Float(frac)), physR * 0.012, popColor(old: globular), rnd(0.6, 0.95))
                }
                // A handful of bright members with glow give the cluster sparkle.
                for _ in 0..<(globular ? 14 : 8) {
                    let dir = unit()
                    let frac = globular ? Float(abs(gauss())) * 0.3 : pow(Float(rnd(0, 1)), 1.0 / 3.0) * 0.9
                    star(center + dir * (physR * frac), physR * 0.02, globular ? popColor(old: true) : starBW, rnd(0.85, 1.0), glow: true)
                }
                // Young clusters keep a breath of blue reflection nebulosity (e.g. Pleiades).
                if !globular && lm.id == "m45" {
                    for _ in 0..<30 { gas(center + shape(g3()) * physR * 0.5, physR * Float(rnd(0.2, 0.4)), reflect, 0.06, 1) }
                }

            case .galaxy:
                let nrm = simd_normalize(g3() + SIMD3(0.0001, 0, 0))
                let gx = simd_normalize(g3() - nrm * simd_dot(nrm, g3())), gy = simd_cross(nrm, gx)
                let warm = SIMD4<Float>(1, 0.86, 0.6, 1)
                // Bulge: a layered warm core + concentrated old stars.
                gas(center, physR * 0.5, warm, 0.30, 1)
                gas(center, physR * 0.24, SIMD4(1, 0.93, 0.78, 1), 0.34, 1)
                cap(center, physR * 0.3)                                          // dense bulge occludes background
                for _ in 0..<140 {
                    let r = abs(Float(gauss())) * physR * 0.16, ang = Float(rnd(0, 2 * .pi))
                    star(center + cos(ang) * r * gx + sin(ang) * r * gy + Float(gauss()) * physR * 0.05 * nrm, physR * 0.02, popColor(old: true), rnd(0.4, 0.85))
                }
                // Central bar.
                let barAngle = Float(rnd(0, .pi))
                let bx = cos(barAngle) * gx + sin(barAngle) * gy, bperp = -sin(barAngle) * gx + cos(barAngle) * gy
                for _ in 0..<120 {
                    let t = Float(rnd(-1, 1)) * physR * 0.5
                    star(center + bx * t + bperp * Float(gauss()) * physR * 0.05 + nrm * Float(gauss()) * physR * 0.04, physR * 0.02, warm, rnd(0.3, 0.6))
                }
                // Two logarithmic spiral arms: young blue stars, pink HII knots, dust.
                let pitch = Float(rnd(4.5, 7.0))
                for arm in 0..<2 {
                    let phase = Float(arm) * .pi + barAngle
                    for s in 0..<300 {
                        let f = Float(s) / 300
                        let rad = physR * (0.14 + 0.86 * f)
                        let theta = phase + pitch * Float(log(Double(rad / (physR * 0.14))))
                        let base = center + cos(theta) * rad * gx + sin(theta) * rad * gy
                        let perp = cos(theta) * gx + sin(theta) * gy, tang = -sin(theta) * gx + cos(theta) * gy
                        let pos = base + perp * Float(gauss()) * physR * 0.04 * (0.6 + f) + nrm * Float(gauss()) * physR * 0.025 + tang * Float(rnd(-1, 1)) * physR * 0.02
                        let r = rnd(0, 1)
                        let c = r < 0.7 ? starBW : (r < 0.9 ? SIMD4<Float>(1, 1, 1, 1) : warm)
                        gas(pos, physR * 0.018, c, (0.5 - 0.25 * Double(f)) * rnd(0.5, 1), 0.5)
                        if rnd(0, 1) < 0.05 {
                            gas(pos, physR * 0.05, haAlpha, 0.4, 0.8)                          // HII knot
                            star(pos, physR * 0.02, starBW, 0.85, glow: true)
                        }
                        if rnd(0, 1) < 0.35 { dustPuff(base - perp * physR * 0.03 + nrm * Float(gauss()) * physR * 0.02, physR * Float(rnd(0.03, 0.07)), rnd(0.2, 0.45)) }
                    }
                }
                // Faint smooth disc field.
                for _ in 0..<160 {
                    let rad = Float(pow(rnd(0, 1), 0.6)) * physR, ang = Float(rnd(0, 2 * .pi))
                    gas(center + cos(ang) * rad * gx + sin(ang) * rad * gy + nrm * Float(gauss()) * physR * 0.05, physR * 0.02, SIMD4(1, 1, 1, 1), 0.12 * rnd(0.5, 1), 0.5)
                }
                // Disc-plane dust (reads as the dark lane when edge-on, e.g. Sombrero).
                for _ in 0..<70 {
                    let rad = Float(rnd(0.1, 0.95)) * physR, ang = Float(rnd(0, 2 * .pi))
                    dustPuff(center + cos(ang) * rad * gx + sin(ang) * rad * gy + nrm * Float(gauss()) * physR * 0.045, physR * Float(rnd(0.04, 0.09)), rnd(0.15, 0.4))
                }

            case .blackHole:
                // Proportions follow Schwarzschild geometry: the dark shadow ≈ 2.6 rs and
                // the disc's inner edge (ISCO) ≈ 3 rs, so the shadow sits just inside a thin
                // bright photon ring, itself just inside the disc's inner rim. The absolute
                // size R is stylised — the true horizon is sub-pixel at galaxy scale — but
                // the shadow/ring/disc ratios are physical. Up close you fly in (easter egg).
                let isSgr = lm.id == "sgr-a"
                let dim = isSgr ? 0.85 : 1.0
                let R = max(8, physR * 10)            // disc outer radius
                let shadowR = R * 0.26                // event-horizon shadow (2.6 rs)
                let ringR = R * 0.30                  // photon ring (~1.5 rs lensed to ~2.6)
                let diskInner = R * 0.34              // disc inner edge (ISCO, 3 rs)
                let beam = ey                         // Doppler-bright (approaching) limb
                let hot = SIMD4<Float>(1, 0.98, 0.92, 1), orange2 = SIMD4<Float>(1, 0.5, 0.18, 1)
                let red2 = SIMD4<Float>(0.85, 0.22, 0.06, 1)
                // Thin accretion disc: hot-white inner → orange → red outer, strongly
                // Doppler-beamed on the approaching limb, with a turbulent swirl.
                for _ in 0..<460 {
                    let ang = rnd(0, 2 * .pi)
                    let u = Float(pow(rnd(0, 1), 0.6))
                    let rr = diskInner + (R - diskInner) * u
                    let dir = Float(cos(ang)) * ex + Float(sin(ang)) * ey
                    let pos = center + dir * rr + ez * Float(gauss()) * R * 0.006   // very thin
                    let t = Double(u)
                    let col = t < 0.5 ? hot + (orange2 - hot) * Float(t * 2)
                                      : orange2 + (red2 - orange2) * Float((t - 0.5) * 2)
                    let tangent = -Float(sin(ang)) * ex + Float(cos(ang)) * ey
                    let dop = 0.5 + 0.5 * Double(simd_dot(tangent, beam))   // 0 receding → 1 approaching
                    let beamBoost = 0.25 + 1.6 * dop * dop                  // relativistic limb brightening
                    gas(pos, R * 0.05, col, (0.5 - 0.28 * t) * beamBoost * dim, 1)
                }
                // Bright photon ring hugging the shadow.
                for _ in 0..<170 {
                    let ang = rnd(0, 2 * .pi)
                    let dir = Float(cos(ang)) * ex + Float(sin(ang)) * ey
                    let tangent = -Float(sin(ang)) * ex + Float(cos(ang)) * ey
                    let dop = 0.5 + 0.5 * Double(simd_dot(tangent, beam))
                    gas(center + dir * ringR, R * 0.02, SIMD4(1, 0.97, 0.88, 1), (0.45 + 0.75 * dop) * dim, 0.8)
                }
                gas(center, shadowR * 2.6, SIMD4(1, 0.62, 0.32, 1), 0.10 * dim, 1)   // soft hot halo
                // Relativistic jets for the microquasars (not quiescent Sgr A*).
                if !isSgr {
                    for s in [-1.0, 1.0] {
                        for i in 0..<40 {
                            let f = Float(i) / 40
                            let pos = center + ez * Float(s) * R * (0.3 + f * 3.0) + (ex * Float(gauss()) + ey * Float(gauss())) * R * 0.05 * (0.4 + f)
                            gas(pos, R * 0.05 * (0.5 + f), SIMD4(0.6, 0.8, 1, 1), 0.16 * (1 - Double(f)) * dim, 1)
                        }
                    }
                }
                // Dark event-horizon shadow: a hard black disc that occludes the disc light
                // and photon ring behind it (normal-blend overlay subtracts the additive glow).
                overlay.append(GalaxySprite(position: center, radius: shadowR, color: SIMD4(0, 0, 0, 1),
                                            minPixel: 2, maxPixel: 1400, softness: 0.08, mode: 0))
            }
        }
    }

    /// Places an image-baked nebula: the normalised particle sheet is oriented to
    /// face Earth (the origin) at the landmark's real position/scale, with per-particle
    /// depth synthesised so it reads as the photo head-on and as a volume when orbited.
    private func appendBakedNebula(_ lm: Landmark, _ model: NebulaParticleSet,
                                   center: SIMD3<Float>, physR: Float, dustC: SIMD4<Float>,
                                   _ additive: inout [GalaxySprite], _ occluder: inout [GalaxySprite],
                                   _ overlay: inout [GalaxySprite]) {
        let half = physR * 1.4                                  // the photo spans a bit past the catalog radius
        let n = simd_length(center) > 1e-3 ? simd_normalize(-center) : SIMD3<Float>(0, 0, 1)  // face Earth
        var right = simd_cross(SIMD3<Float>(0, 1, 0), n)
        right = simd_length(right) < 1e-4 ? SIMD3<Float>(1, 0, 0) : simd_normalize(right)
        let up = simd_cross(n, right)

        var rng = SeededGenerator(seed: lm.id.unicodeScalars.reduce(UInt64(977), { $0 &* 31 &+ UInt64($1.value) }))
        func gauss() -> Float {
            let u1 = Double.random(in: 1e-6...1, using: &rng), u2 = Double.random(in: 0...1, using: &rng)
            return Float((-2 * log(u1)).squareRoot() * cos(2 * .pi * u2))
        }
        let lumW = SIMD3<Float>(0.2126, 0.7152, 0.0722)

        // Dark structure comes for free from the gas density (the bake places few
        // particles where the photo is dark), so we deliberately do NOT draw a dark
        // overlay here — it would punch opaque holes into the additive light.
        _ = dustC
        // Invisible depth caps trace the nebula's *bright* shape into the depth buffer so
        // background stars behind the dense gas are occluded — while genuinely dark gaps
        // (e.g. Pacman's mouth) get no cap, so stars correctly show through them.
        // Subsampled (every Nth bright particle) to keep the occluder set small.
        let capStride = max(1, model.gas.count / 700)
        for (i, p) in model.gas.enumerated() {
            let lum = simd_dot(p.color, lumW)
            let depth = gauss() * half * 0.11 * (0.5 + lum)    // some volume, but tight enough to avoid face-on gaps
            let world = center + (p.pos.x * half) * right + (p.pos.y * half) * up + depth * n
            if lum > 0.3 && i % capStride == 0 {
                occluder.append(GalaxySprite(position: world, radius: half * 0.06, color: SIMD4(0, 0, 0, 0),
                                             minPixel: 0, maxPixel: 1400, softness: 0, mode: 0))
            }
            // A soft bloom underglow fuses neighbours into a smooth cloud; a tighter
            // sprite adds definition. Opacities kept low so the dense core builds up a
            // bright-but-coloured centre instead of saturating to flat white.
            let bloom = min(0.022, Double(lum) * 0.032)
            additive.append(GalaxySprite(position: world, radius: half * 0.075,
                                         color: SIMD4(p.color.x, p.color.y, p.color.z, Float(bloom)),
                                         minPixel: 0, maxPixel: 1400, softness: 1, mode: 0))
            let op = min(0.085, max(0.016, Double(lum) * 0.10))
            additive.append(GalaxySprite(position: world, radius: half * 0.04,
                                         color: SIMD4(p.color.x, p.color.y, p.color.z, Float(op)),
                                         minPixel: 0, maxPixel: 1400, softness: 0.9, mode: 0))
        }
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
            // Only scan stars in view (octree frustum cull) rather than the whole catalogue.
            let candidates = octree?.query(planes: frustumPlanes(viewProjection)) ?? Array(stars.indices)
            for idx in candidates {
                let star = stars[idx]
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
        // Brightest (largest) first, so the level-of-detail cap keeps the prominent
        // ones — and so an array index doubles as a brightness rank.
        result.sort { $0.baseSize > $1.baseSize }
        stars = result
        // Spatial index for frustum culling + picking (built once; positions static).
        octree = PointOctree(points: result.map { $0.position })
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

        // Palette buckets (see backdropPalette): 0 cool-blue arm · 1 warm-white arm ·
        // 2 pink HII · 3 disc haze · 4 gold bulge · 5 pale halo · 6 blue clusters.
        let armCool = 0, armWarm = 1, hiiBucket = 2, discBucket = 3, bulgeBucket = 4, haloBucket = 5, blueBucket = 6

        let rMax: Float = 16500
        let rInner: Float = 2400   // arms emanate from the ends of the bar
        let arms = 4
        let k: Float = 0.235       // logarithmic-spiral winding — a touch more open/sweeping

        // Spiral angle for a given galactocentric radius.
        func spiralAngle(_ r: Float) -> Float { Float(log(Double(r / rInner))) / k }

        var points: [BackdropPoint] = []
        var dust: [BackdropPoint] = []

        // Two major arms (from the bar ends) + two minor arms, like the real galaxy.
        // Each arm has a bright ridge of stars, a colour gradient (warm inside → cool
        // blue outside), pink HII knots, blue young-cluster tips, feathered spurs, and
        // a dark dust lane riding its inner edge.
        for armIndex in 0..<arms {
            let offset = Float(armIndex) * (.pi / 2)
            let major = (armIndex % 2 == 0)
            // Denser + smaller points read as smooth arm structure rather than
            // chunky dots; the bloom pass fuses them into a continuous lane.
            let starCount = major ? 5200 : 2800
            let knotCount = major ? 170 : 90
            let weight: Float = major ? 1.0 : 0.6
            for _ in 0..<starCount {
                let r = rInner + rand(0, 1) * (rMax - rInner)
                let rr = r + gaussian() * (r * 0.045 + 200)
                let angle = spiralAngle(r) + offset + gaussian() * 0.085
                let h = gaussian() * (110 + r * 0.010)
                let frac = r / rMax
                let bright = max(0.06, 0.42 - 0.26 * frac) * weight
                // Warm-white toward the core, cool-blue toward the rim; a sprinkle of
                // bright young-blue clusters out along the arms.
                let warmProb = Double(max(0, 0.85 - frac * 1.25))
                let bucket: Int
                if rand(0, 1) < 0.05 && frac > 0.25 { bucket = blueBucket }
                else { bucket = Double.random(in: 0...1, using: &rng) < warmProb ? armWarm : armCool }
                points.append(BackdropPoint(
                    position: place(cos(angle) * rr, sin(angle) * rr, h),
                    colorBucket: bucket,
                    baseOpacity: Double(bright) * Double(rand(0.45, 1)),
                    size: CGFloat(rand(0.5, 1.3))))
            }
            // Feathered spurs: short segments branching off the arm, breaking its
            // outline so the arms look turbulent and rich rather than clean ribbons.
            let spurs = major ? 14 : 8
            for _ in 0..<spurs {
                let r0 = rInner + rand(0.12, 0.92) * (rMax - rInner)
                let a0 = spiralAngle(r0) + offset
                let spurAng = a0 + rand(-0.9, 0.9)
                let len = rand(300, 1100)
                let cx0 = cos(a0) * r0, cy0 = sin(a0) * r0
                for _ in 0..<55 {
                    let t = rand(0, 1)
                    let cx = cx0 + cos(spurAng) * len * t + gaussian() * 120
                    let cy = cy0 + sin(spurAng) * len * t + gaussian() * 120
                    points.append(BackdropPoint(
                        position: place(cx, cy, gaussian() * 130),
                        colorBucket: rand(0, 1) < 0.5 ? armCool : armWarm,
                        baseOpacity: Double(rand(0.08, 0.3)) * Double(weight),
                        size: CGFloat(rand(0.45, 1.1))))
                }
            }
            // Pink HII regions studding the arms — the iconic star-forming knots.
            for _ in 0..<knotCount {
                let r = rInner + rand(0.05, 1) * (rMax - rInner)
                let angle = spiralAngle(r) + offset + gaussian() * 0.05
                let cx = cos(angle) * r, cy = sin(angle) * r
                points.append(BackdropPoint(
                    position: place(cx + gaussian() * 170, cy + gaussian() * 170, gaussian() * 110),
                    colorBucket: hiiBucket,
                    baseOpacity: Double(rand(0.3, 0.62)) * Double(weight),
                    size: CGFloat(rand(0.8, 1.8))))
            }
            // Dust lane: a dark, thin filament riding just inside the arm ridge, with
            // its own clumpy sub-structure — drawn later to subtract light from the glow.
            for _ in 0..<2200 {
                let r = rInner + rand(0.04, 1) * (rMax - rInner)
                let angle = spiralAngle(r) + offset - 0.085 + gaussian() * 0.05   // inner edge
                let rr = r + gaussian() * (r * 0.02 + 90)
                dust.append(BackdropPoint(
                    position: place(cos(angle) * rr, sin(angle) * rr, gaussian() * 70),
                    colorBucket: 0,
                    baseOpacity: Double(rand(0.25, 0.7)) * Double(weight),
                    size: CGFloat(rand(1.4, 3.4))))
            }
        }

        // Diffuse disc, exponential falloff — fills between the arms with a faint haze.
        for _ in 0..<5200 {
            let r = sqrt(rand(0, 1)) * rMax
            let angle = rand(0, 2 * .pi)
            let h = gaussian() * (100 + r * 0.010)
            let bright = max(0.022, 0.12 * exp(-r / 8500))
            points.append(BackdropPoint(
                position: place(cos(angle) * r, sin(angle) * r, h),
                colorBucket: discBucket,
                baseOpacity: Double(bright) * Double(rand(0.4, 1)),
                size: CGFloat(rand(0.45, 1.0))))
        }

        // Central bar + bulge — warm, bright, elongated (the Milky Way is a barred spiral).
        for _ in 0..<5000 {
            let x = gaussian() * 2900      // elongated along axisA → the bar
            let y = gaussian() * 1100
            let z = gaussian() * 680
            let d = (x * x / (2900 * 2900) + y * y / (1100 * 1100) + z * z / (680 * 680)).squareRoot()
            let opacity = min(0.9, max(0.10, 0.9 - Double(d) * 0.66))
            points.append(BackdropPoint(
                position: place(x, y, z),
                colorBucket: bulgeBucket,
                baseOpacity: opacity * Double(rand(0.55, 1)),
                size: CGFloat(rand(0.6, 1.6))))
        }

        // Faint spherical stellar halo — old stars enveloping the disc, giving the
        // galaxy a sense of depth and grandeur beyond the flat plane.
        for _ in 0..<2600 {
            let dir = SIMD3<Float>(gaussian(), gaussian(), gaussian())
            let rad = pow(rand(0, 1), 0.5) * 9000 + 600
            let p = simd_normalize(dir + SIMD3(1e-5, 0, 0)) * rad
            points.append(BackdropPoint(
                position: centre + p.x * axisA + p.y * axisB + p.z * up,
                colorBucket: haloBucket,
                baseOpacity: Double(rand(0.02, 0.12)) * Double(max(0.1, 1 - rad / 9600)),
                size: CGFloat(rand(0.4, 0.9))))
        }

        backdrop = points
        backdropDust = dust
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

/// The view-frustum planes (inside ⇔ `dot(n, p) + w ≥ 0`) extracted from a
/// view-projection matrix via Gribb–Hartmann. We return the four sides plus a
/// "front" plane (clip.w ≥ 0, matching `project`'s behind-camera cull) and omit
/// near/far — the Galaxy Map wants distant stars, just not ones off-screen or behind.
private func frustumPlanes(_ vp: simd_float4x4) -> [SIMD4<Float>] {
    func row(_ i: Int) -> SIMD4<Float> {
        SIMD4(vp.columns.0[i], vp.columns.1[i], vp.columns.2[i], vp.columns.3[i])
    }
    let r0 = row(0), r1 = row(1), r3 = row(3)
    return [r3, r3 + r0, r3 - r0, r3 + r1, r3 - r1]   // front, left, right, bottom, top
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
