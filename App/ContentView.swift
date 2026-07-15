import SwiftUI
import UIKit
import ARKit
import AVFoundation
import simd
import CelestialCore

// SwiftUI also declares `Angle`; in this file we always mean the astronomy one.
private typealias Angle = CelestialCore.Angle

private enum SkyMode: Hashable { case virtual, ar }

/// The sky visualizer. "Sky" mode draws the sky on a dark background from the
/// device attitude; "AR" mode overlays it on the live camera via ARKit, with a
/// manual calibration nudge for precision. Both share one renderer (`SkyCamera`).
struct ContentView: View {
    @State private var provider = SkyMotionProvider()
    @State private var store = StarCatalogStore()
    @State private var exoStore = ExoplanetStore()
    @State private var arController = ARCameraController()
    @State private var filters = SkyFilters()
    @State private var showFilters = false
    @State private var showMenu = false
    @State private var uiRotation = 0.0   // chrome rotation (degrees) to stay upright as the phone tilts
    @Environment(\.openURL) private var openURL

    @State private var mode: SkyMode = .virtual
    @State private var starField: [StarPoint] = []          // sorted brightest-first
    @State private var constellationPaths: [ConstellationPath] = []
    // Ecliptic overlay: the ecliptic sampled as world directions and the live
    // planets — all recomputed on the calm 1.5 s refresh, never per frame.
    @State private var eclipticPoints: [SIMD3<Double>] = []
    @State private var planetGlyphs: [SkyGlyph] = []

    @State private var fieldOfView = 65.0
    @State private var zoomAnchor = 65.0
    @State private var selection: StarSelection?

    // Time scrubber: an offset (seconds) from "now" applied to every position
    // calculation, so you can run the sky forward/back to watch the Moon's phase,
    // planets, and rising/setting. Off (live) by default — zero offset.
    @State private var timeOffset: TimeInterval = 0
    @State private var showTimeScrubber = false
    private var isTimeShifted: Bool { abs(timeOffset) > 1 }
    private func shifted(_ date: Date) -> Date { date.addingTimeInterval(timeOffset) }

    // AR calibration (azimuth offset, degrees) supplying absolute heading.
    // Until the user manually aligns, it's auto-seeded from the compass (CoreMotion);
    // a manual Align freezes a precise value.
    @State private var azimuthOffset = 0.0
    @State private var manuallyCalibrated = false
    @State private var autoSeeded = false
    @State private var lastSkyRefresh = Date.distantPast   // throttles the full star rebuild
    @State private var calibrating = false
    @State private var calibrationOptions: [CalibrationOption] = []
    @State private var calibrationTarget = "Sun"

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                if mode == .ar {
                    Color.black
                } else {
                    background
                }

                // Only the fast-moving sky lives in TimelineView (rebuilt every frame).
                // Interactive controls are kept OUT of it, else the 60fps rebuilds
                // cancel their taps (the mode toggle wouldn't switch).
                TimelineView(.animation) { timeline in
                    let camera = makeSkyCamera(size: size)
                    let effectiveFOV = mode == .virtual ? fieldOfView : 55.0
                    ZStack {
                        // Live camera passthrough drawn in the SAME layer as the sky.
                        // A separate underlying AR view (RealityKit/SceneKit, or a plain
                        // Image) rendered black here — composing it inside the working
                        // sky TimelineView is what actually shows the feed.
                        if mode == .ar, let cameraImage = arController.currentCameraImage() {
                            Image(decorative: cameraImage, scale: 1)
                                .resizable()
                                .scaledToFill()
                                .frame(width: size.width, height: size.height)
                                .clipped()
                        }
                        if let camera {
                            skyCanvas(camera: camera, effectiveFOV: effectiveFOV, size: size)
                            if filters.showSunMoon,
                               let state = solarState(camera: camera, size: size, date: shifted(timeline.date)) {
                                bodyNodes(state)
                            }
                        }
                    }
                }

                reticle
                    .accessibilityHidden(true)

                // Sky taps/zoom, below the chrome.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(tapGesture(size: size))
                    .simultaneousGesture(zoomGesture)

                skyStatusOverlay

                chrome(size: size, safe: .deviceSafeArea)
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .onAppear {
            provider.start()
            store.loadIfNeeded()
            exoStore.loadIfNeeded()
            // The full-screen menu makes this view disappear (pausing the sensors);
            // on return, resume the AR session too if we're in AR mode.
            if mode == .ar { arController.start() }
        }
        .onDisappear { provider.stop(); arController.stop() }
        .onChange(of: mode) { _, newMode in
            if newMode == .ar {
                // A fresh AR session has an arbitrary heading; re-seed from compass.
                arController.start()
                manuallyCalibrated = false
                autoSeeded = false
            } else {
                arController.stop()
            }
        }
        .onChange(of: filters) { _, _ in refreshSky() }
        .task {
            while !Task.isCancelled {
                updateInterfaceRotation()      // responsive: chrome must track tilt promptly
                updateAutoCalibration()
                // The star field's horizontal coordinates drift on the sidereal
                // timescale, so rebuilding the whole catalog 5×/s is wasteful — the
                // per-frame motion is handled by the Canvas projection. Refresh calmly.
                if Date().timeIntervalSince(lastSkyRefresh) > 1.5 {
                    refreshSky()
                    lastSkyRefresh = Date()
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        .sheet(isPresented: $showFilters) {
            FilterSheet(filters: $filters, catalog: store.catalog)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showMenu) {
            MoreMenuView(store: store, exo: exoStore)
        }
    }

    // MARK: Sky rendering (stars + constellations + labels, one Canvas)

    private func skyCanvas(camera: SkyCamera, effectiveFOV: Double, size: CGSize) -> some View {
        let labelLimit = labelMagnitudeLimit(effectiveFOV)
        return Canvas { context, _ in
            // Constellation lines.
            if filters.showConstellations {
                let stroke = GraphicsContext.Shading.color(Color(red: 0.45, green: 0.6, blue: 1.0).opacity(0.32))
                for path in constellationPaths {
                    var shape = Path()
                    for line in path.polylines {
                        var previous: CGPoint?
                        for vertex in line {
                            if let point = camera.projectDirection(vertex), within(point, size, margin: 500) {
                                if let previous { shape.move(to: previous); shape.addLine(to: point) }
                                previous = point
                            } else {
                                previous = nil
                            }
                        }
                    }
                    context.stroke(shape, with: stroke, lineWidth: 0.8)
                }
            }

            // Ecliptic (the Sun's path across the sky), drawn behind the stars.
            if filters.showEcliptic {
                var ecliptic = Path()
                var previous: CGPoint?
                for direction in eclipticPoints {
                    if let point = camera.projectDirection(direction), within(point, size, margin: 500) {
                        if let previous { ecliptic.move(to: previous); ecliptic.addLine(to: point) }
                        previous = point
                    } else {
                        previous = nil
                    }
                }
                context.stroke(ecliptic, with: .color(Self.eclipticGold.opacity(0.30)), lineWidth: 3)
                context.stroke(ecliptic, with: .color(Self.eclipticGold.opacity(0.65)), lineWidth: 1)
            }

            // Stars.
            for star in starField {
                guard let point = camera.projectDirection(star.direction), within(point, size, margin: 4) else { continue }
                let radius = starRadius(star.magnitude)
                if star.magnitude < 1.5 {
                    let g = radius * 3
                    context.fill(Path(ellipseIn: CGRect(x: point.x - g, y: point.y - g, width: g * 2, height: g * 2)),
                                 with: .color(star.color.opacity(0.18)))
                }
                context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(star.color))
            }

            // Labels (constellation names, then stars by brightness), de-cluttered.
            var occupied: [CGRect] = []
            func place(_ text: Text, at point: CGPoint) {
                let resolved = context.resolve(text)
                let measured = resolved.measure(in: CGSize(width: 200, height: 60))
                let rect = CGRect(x: point.x - measured.width / 2, y: point.y - measured.height / 2,
                                  width: measured.width, height: measured.height)
                guard rect.minX > 0, rect.maxX < size.width, rect.minY > 44, rect.maxY < size.height - 130 else { return }
                if occupied.contains(where: { $0.intersects(rect) }) { return }
                occupied.append(rect.insetBy(dx: -4, dy: -4))
                context.draw(resolved, at: point)
            }

            if filters.showConstellations {
                for path in constellationPaths {
                    if let point = camera.projectDirection(path.labelDirection), within(point, size, margin: 0) {
                        place(Text(path.id.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(red: 0.6, green: 0.72, blue: 1.0).opacity(0.55)), at: point)
                    }
                }
            }
            if filters.showLabels {
                for star in starField where star.label != nil && star.magnitude <= labelLimit {
                    guard let point = camera.projectDirection(star.direction), within(point, size, margin: 0) else { continue }
                    place(Text(star.label ?? "")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82)), at: CGPoint(x: point.x, y: point.y + 9))
                }
            }

            // The planets on top.
            if filters.showEcliptic {
                for planet in planetGlyphs {
                    guard let point = camera.projectDirection(planet.direction), within(point, size, margin: 0) else { continue }
                    let halo = 5.0
                    context.fill(Path(ellipseIn: CGRect(x: point.x - halo, y: point.y - halo, width: halo * 2, height: halo * 2)),
                                 with: .color(planet.color.opacity(0.25)))
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)),
                                 with: .color(planet.color))
                    place(Text(planet.symbol).font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(planet.color), at: CGPoint(x: point.x, y: point.y - 14))
                    place(Text(planet.name).font(.system(size: 9, weight: .medium))
                        .foregroundStyle(planet.color.opacity(0.85)), at: CGPoint(x: point.x, y: point.y + 11))
                }
            }
        }
    }

    private func bodyNodes(_ state: SolarState) -> some View {
        ForEach(state.bodies) { body in
            if let point = body.screen {
                VStack(spacing: 4) {
                    Circle()
                        .fill(body.color)
                        .frame(width: body.size, height: body.size)
                        .shadow(color: body.color.opacity(0.9), radius: body.glow)
                        .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 0.5))
                    Text(body.name).font(.caption.weight(.semibold)).foregroundStyle(.white)
                }
                .shadow(radius: 2)
                .rotationEffect(.degrees(uiRotation))
                .position(point)
            }
        }
    }

    // MARK: Chrome

    private var background: some View {
        LinearGradient(colors: [Color(red: 0.02, green: 0.03, blue: 0.12), .black],
                       startPoint: .top, endPoint: .bottom)
    }

    private var reticle: some View {
        Circle().stroke(.white.opacity(0.3), lineWidth: 1).frame(width: 44, height: 44)
    }

    /// Explains an empty sky instead of leaving it blank: the stars only render once
    /// location + motion + catalog are all ready. A fresh sideload resets the
    /// location permission, which otherwise silently empties the whole view.
    private struct SkyStatus { let symbol: String; let message: String; let showSettings: Bool }

    private var skyStatus: SkyStatus? {
        if !provider.isAuthorized {
            let denied = provider.authorization == .denied || provider.authorization == .restricted
            return SkyStatus(
                symbol: "location.slash",
                message: denied ? "Astrolabe needs location access to place the sky.\nEnable it in Settings."
                                : "Allow location access so Astrolabe can compute your sky.",
                showSettings: denied)
        }
        if !provider.hasLocation {
            return SkyStatus(symbol: "location.magnifyingglass", message: "Finding your location…", showSettings: false)
        }
        if store.catalog == nil {
            return SkyStatus(symbol: "sparkles", message: "Loading star catalog…", showSettings: false)
        }
        if mode == .virtual && provider.rotationMatrix == nil {
            return SkyStatus(symbol: "gyroscope", message: "Calibrating motion sensors…", showSettings: false)
        }
        if mode == .ar {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .denied, .restricted:
                return SkyStatus(symbol: "video.slash",
                                 message: "Camera access is needed for AR mode.\nEnable it in Settings.",
                                 showSettings: true)
            default: break
            }
            if arController.currentFrame == nil {
                return SkyStatus(symbol: "camera.viewfinder", message: "Starting AR camera…", showSettings: false)
            }
        }
        return nil
    }

    @ViewBuilder
    private var skyStatusOverlay: some View {
        if let status = skyStatus {
            VStack(spacing: 14) {
                LuminousGlyph(symbol: status.symbol, tint: Theme.accent, size: 72, glyphSize: 32)
                Text(status.message)
                    .font(.callout).multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
                if status.showSettings {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(LuminousButtonStyle())
                } else {
                    ProgressView().tint(Theme.accent).padding(.top, 2)
                }
            }
            .padding(28)
            .luminousSurface(Theme.accent, cornerRadius: 24, glow: 16)
            .padding(40)
        }
    }

    /// The chrome rides the device, not the screen: as the phone tilts, the whole
    /// control cluster orbits — as one rigid, upright unit — to whichever screen
    /// edge is physically *up*, and the readout to the edge that's *down*. When the
    /// phone is upright they return to the portrait top/bottom. `uiRotation` already
    /// snaps to the nearest 90°, so the cluster slides smoothly around the corner.
    private func chrome(size: CGSize, safe: EdgeInsets) -> some View {
        let landscape = quadrant == 1 || quadrant == 3
        return VStack(spacing: 12) {
            controlBar
            if let selection { selectionCard(selection) }
            if showTimeScrubber { timeScrubber() }
            if mode == .ar { calibrationBar() }

            Spacer(minLength: 0)

            if filters.showStars && filters.showColourKey { StarColorLegend() }

            // Live readout, refreshed calmly (kept out of the 60fps render loop).
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let camera = makeSkyCamera(size: size)
                bottomPanel(camera.flatMap { solarState(camera: $0, size: size, date: shifted(Date())) })
            }
        }
        .padding(.horizontal)
        .padding(.top, edgeInset(quadrant, safe) + 8)
        .padding(.bottom, edgeInset((quadrant + 2) % 4, safe) + 6)
        // Lay the chrome out in a frame matching the *rotated* screen, then spin the
        // whole thing: the controls stay pinned to the physical top edge and the
        // readout to the physical bottom, hugging whichever way the phone is tilted.
        .frame(width: landscape ? size.height : size.width,
               height: landscape ? size.width : size.height)
        .rotationEffect(.degrees(uiRotation))
        .frame(width: size.width, height: size.height)
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            CircleIconButton(label: "Menu", systemImage: "square.grid.2x2") { showMenu = true }
            Spacer()
            Picker("Mode", selection: $mode) {
                Text("Sky").tag(SkyMode.virtual)
                Text("AR").tag(SkyMode.ar)
            }
            .pickerStyle(.segmented)
            .frame(width: 132)
            .sensoryFeedback(.selection, trigger: mode)
            Spacer()
            CircleIconButton(label: "Time travel", systemImage: isTimeShifted ? "clock.arrow.2.circlepath" : "clock",
                             tint: .cyan, isActive: showTimeScrubber || isTimeShifted) {
                withAnimation { showTimeScrubber.toggle() }
            }
            CircleIconButton(label: "Sky filters", systemImage: "slider.horizontal.3") { showFilters = true }
        }
    }

    @ViewBuilder
    private func timeScrubber() -> some View {
        VStack(spacing: 6) {
            HStack {
                Label(timeOffsetLabel, systemImage: "clock")
                    .font(.caption.monospacedDigit()).foregroundStyle(.white)
                Spacer()
                if isTimeShifted {
                    Button("Now") { withAnimation { timeOffset = 0 }; refreshSky() }
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                }
            }
            Slider(value: $timeOffset, in: -12 * 3600 ... 12 * 3600, step: 300) { editing in
                if !editing { refreshSky() }   // rebuild the star field on release
            }
            .tint(.cyan)
        }
        .padding(10)
        .luminousSurface(.cyan, cornerRadius: 22, glow: 8)
    }

    /// "Live · Sat 21:14" when at the present instant, otherwise the shifted clock
    /// time and the signed offset, e.g. "Sat 03:14 · +6h 0m".
    private var timeOffsetLabel: String {
        let date = shifted(Date())
        let clock = Self.scrubberFormatter.string(from: date)
        if !isTimeShifted { return "Live · \(clock)" }
        let total = Int(abs(timeOffset) / 60)
        let sign = timeOffset >= 0 ? "+" : "−"
        return "\(clock) · \(sign)\(total / 60)h \(total % 60)m"
    }

    private static let scrubberFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE HH:mm"; return f
    }()

    /// Which screen edge is physically up: 0 top (portrait), 1 left, 2 bottom
    /// (upside down), 3 right. Derived from the snapped chrome rotation.
    private var quadrant: Int { (((Int((-uiRotation / 90).rounded())) % 4) + 4) % 4 }

    /// Safe-area inset of the portrait edge that currently sits at position `q`
    /// (0 top … 3 right). In landscape the physical top/bottom are screen *sides*,
    /// which have ~no inset, so the chrome hugs them instead of leaving island gaps.
    private func edgeInset(_ q: Int, _ safe: EdgeInsets) -> CGFloat {
        switch q {
        case 0: return max(safe.top, 12)
        case 1: return max(safe.leading, 12)
        case 2: return max(safe.bottom, 12)
        default: return max(safe.trailing, 12)
        }
    }

    private func selectionCard(_ selection: StarSelection) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selection.title).font(.headline).foregroundStyle(.white)
                Text(selection.subtitle).font(.caption).foregroundStyle(.white.opacity(0.6))
                if let detail = selection.detail {
                    Text(detail).font(.caption2).foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Button { self.selection = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss \(selection.title)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 2)
        .padding(.vertical, 2)
        .luminousSurface()
    }

    @ViewBuilder
    private func calibrationBar() -> some View {
        if calibrating {
            HStack(spacing: 10) {
                Menu {
                    ForEach(calibrationOptions) { option in
                        Button(option.label) { calibrationTarget = option.id }
                    }
                } label: {
                    Label(calibrationTargetLabel, systemImage: "scope")
                        .font(.subheadline).foregroundStyle(Theme.accent)
                }
                Spacer()
                Button("Align") { alignCalibration() }.buttonStyle(LuminousButtonStyle())
                Button("Cancel") { calibrating = false }.foregroundStyle(.white.opacity(0.7))
            }
            .padding(8).luminousSurface(Theme.accent, cornerRadius: 26, glow: 8)
        } else {
            HStack(spacing: 12) {
                Button { startCalibration() } label: {
                    Label("Calibrate", systemImage: "scope").font(.subheadline)
                }
                if manuallyCalibrated {
                    Text("aligned ✓").font(.caption).foregroundStyle(.green)
                    Button("Reset") {
                        manuallyCalibrated = false
                        autoSeeded = false
                    }
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
                } else {
                    Text("auto · tap to refine").font(.caption).foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(10).background(.ultraThinMaterial, in: .capsule)
            .sensoryFeedback(.success, trigger: manuallyCalibrated)
        }
    }

    @ViewBuilder
    private func bottomPanel(_ state: SolarState?) -> some View {
        VStack(spacing: 10) {
            if let state {
                if filters.showSunMoon {
                    ForEach(state.bodies) { body in bodyRow(body) }
                    Divider().overlay(.white.opacity(0.2))
                }
                Text(String(format: "Pointing  %@ %.0f°  ·  alt %+.0f°",
                            compass(state.pointing.azimuth),
                            state.pointing.azimuth.degrees, state.pointing.altitude.degrees))
                    .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
            } else {
                Text(statusMessage).font(.callout).multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(14)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }

    private func bodyRow(_ body: ProjectedBody) -> some View {
        let inView = abs(body.deltaAzimuth) < 12 && abs(body.deltaAltitude) < 12
        return HStack(spacing: 10) {
            Circle().fill(body.color).frame(width: 9, height: 9)
            Text(body.name).font(.subheadline.weight(.medium)).foregroundStyle(.white)
            Spacer()
            Text(String(format: "az %.0f° alt %+.0f°", body.azimuth.degrees, body.altitude.degrees))
                .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.5))
            Text(inView ? "● here" : turnHint(body))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(inView ? .green : .white.opacity(0.85))
                .frame(width: 92, alignment: .trailing)
        }
    }

    // MARK: Gestures

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in if mode == .virtual { fieldOfView = min(95, max(18, zoomAnchor / value)) } }
            .onEnded { _ in zoomAnchor = fieldOfView }
    }

    private func tapGesture(size: CGSize) -> some Gesture {
        SpatialTapGesture().onEnded { event in identify(at: event.location, size: size) }
    }

    private func identify(at location: CGPoint, size: CGSize) {
        guard let camera = makeSkyCamera(size: size), let catalog = store.catalog else { return }
        var best: (distance: CGFloat, id: Int)?
        for star in starField {
            guard let point = camera.projectDirection(star.direction) else { continue }
            let distance = hypot(point.x - location.x, point.y - location.y)
            if distance < 30, best == nil || distance < best!.distance { best = (distance, star.id) }
        }
        if let best, let star = catalog.star(id: best.id) {
            selection = StarSelection(star: star)
        } else {
            selection = nil
        }
    }

    // MARK: Camera & state

    private func makeSkyCamera(size: CGSize) -> SkyCamera? {
        switch mode {
        case .virtual:
            guard let rotation = provider.rotationMatrix else { return nil }
            return .motion(rotation: rotation, fieldOfView: .degrees(fieldOfView), size: size)
        case .ar:
            guard let frame = arController.currentFrame else { return nil }
            return .ar(camera: frame.camera, azimuthOffset: .degrees(azimuthOffset), size: size)
        }
    }

    private func solarState(camera: SkyCamera, size: CGSize, date: Date) -> SolarState? {
        guard let latitude = provider.latitude, let longitude = provider.longitude else { return nil }
        let location = GeographicLocation(latitude: .degrees(latitude), longitude: .degrees(longitude))
        let jd = JulianDay(date)
        let pointing = camera.pointing

        func make(_ name: String, _ color: Color, _ size2: CGFloat, _ glow: CGFloat,
                  _ equatorial: EquatorialCoordinates) -> ProjectedBody {
            let horizon = CoordinateTransform.horizontal(equatorial, at: location, time: jd)
            // Atmospheric refraction lifts a body's apparent altitude (≈34′ at the
            // horizon, ~0 overhead) — apply it so the luminaries sit where the eye
            // actually sees them, especially near the horizon.
            let altitude = Refraction.apparentAltitude(fromTrue: horizon.altitude)
            let direction = worldDirection(azimuth: horizon.azimuth, altitude: altitude)
            return ProjectedBody(
                id: name, name: name, color: color, size: size2, glow: glow,
                azimuth: horizon.azimuth, altitude: altitude,
                screen: camera.projectDirection(direction),
                deltaAzimuth: signedDelta(horizon.azimuth.degrees - pointing.azimuth.degrees),
                deltaAltitude: altitude.degrees - pointing.altitude.degrees
            )
        }

        return SolarState(pointing: pointing, bodies: [
            make("Sun", .orange, 24, 26, Sun.position(at: jd)),
            // The Moon is close enough that topocentric parallax shifts it up to ~1°
            // from its geocentric position — correct it for the observer's location.
            make("Moon", Color(white: 0.92), 20, 18, Moon.topocentric(at: jd, observer: location)),
        ])
    }

    private func refreshSky() {
        guard let latitude = provider.latitude, let longitude = provider.longitude else {
            if !starField.isEmpty { starField = [] }
            if !constellationPaths.isEmpty { constellationPaths = [] }
            if !eclipticPoints.isEmpty { eclipticPoints = []; planetGlyphs = [] }
            return
        }
        let location = GeographicLocation(latitude: .degrees(latitude), longitude: .degrees(longitude))
        let jd = JulianDay(shifted(Date()))

        func toWorld(raDegrees: Double, decDegrees: Double) -> SIMD3<Double> {
            let horizon = CoordinateTransform.horizontal(
                EquatorialCoordinates(rightAscension: .degrees(raDegrees), declination: .degrees(decDegrees)),
                at: location, time: jd)
            return worldDirection(azimuth: horizon.azimuth, altitude: horizon.altitude)
        }

        if filters.showStars, let catalog = store.catalog {
            let limit = filters.magnitudeLimit
            let includeBelow = filters.showBelowHorizon
            var points: [StarPoint] = []
            points.reserveCapacity(catalog.count)
            for star in catalog.stars where star.apparentMagnitude <= limit {
                let horizon = CoordinateTransform.horizontal(star.equatorial, at: location, time: jd)
                if !includeBelow && horizon.altitude.degrees < -1 { continue }
                points.append(StarPoint(
                    id: star.id,
                    direction: worldDirection(azimuth: horizon.azimuth, altitude: horizon.altitude),
                    magnitude: star.apparentMagnitude,
                    color: starColor(star.colorIndex),
                    label: star.properName ?? star.bayerFlamsteed))
            }
            points.sort { $0.magnitude < $1.magnitude }
            starField = points
        } else if !starField.isEmpty {
            starField = []
        }

        if filters.showConstellations {
            constellationPaths = store.constellations.map { constellation in
                var sum = SIMD3<Double>(0, 0, 0)
                var count = 0.0
                let polylines = constellation.polylines.map { line -> [SIMD3<Double>] in
                    line.map { point in
                        let world = toWorld(raDegrees: point.x, decDegrees: point.y)
                        sum += world; count += 1
                        return world
                    }
                }
                let centroid = count > 0 ? simd_normalize(sum / count) : SIMD3<Double>(0, 0, 1)
                return ConstellationPath(id: constellation.id, polylines: polylines, labelDirection: centroid)
            }
        } else if !constellationPaths.isEmpty {
            constellationPaths = []
        }

        if filters.showEcliptic {
            let obliquity = Earth.meanObliquity(at: jd)
            func direction(eclipticLongitude lon: Double, latitude beta: Double = 0) -> SIMD3<Double> {
                let equatorial = CoordinateTransform.equatorial(
                    fromEcliptic: EclipticCoordinates(longitude: .degrees(lon), latitude: .degrees(beta)),
                    obliquity: obliquity)
                let horizon = CoordinateTransform.horizontal(equatorial, at: location, time: jd)
                return worldDirection(azimuth: horizon.azimuth, altitude: horizon.altitude)
            }

            // The ecliptic, sampled every 3° around the full circle.
            eclipticPoints = stride(from: 0.0, through: 360.0, by: 3.0).map { direction(eclipticLongitude: $0) }

            // The live planets at their true positions on the sky.
            planetGlyphs = Planet.allCases.map { planet in
                let horizon = CoordinateTransform.horizontal(Planets.position(planet, at: jd), at: location, time: jd)
                return SkyGlyph(direction: worldDirection(azimuth: horizon.azimuth, altitude: horizon.altitude),
                                symbol: Self.planetSymbol(planet), name: Self.planetName(planet),
                                color: Self.planetColor(planet))
            }
        } else if !eclipticPoints.isEmpty {
            eclipticPoints = []; planetGlyphs = []
        }
    }

    // MARK: Ecliptic overlay helpers

    static let eclipticGold = Color(red: 1.0, green: 0.84, blue: 0.45)

    private static func planetSymbol(_ p: Planet) -> String {
        // Append U+FE0E so ♀/♂ render as line-art, never colour emoji (see CLAUDE.md).
        let base: String
        switch p {
        case .mercury: base = "☿"; case .venus: base = "♀"; case .mars: base = "♂"; case .jupiter: base = "♃"
        case .saturn: base = "♄"; case .uranus: base = "♅"; case .neptune: base = "♆"; case .pluto: base = "♇"
        }
        return base + "\u{FE0E}"
    }

    private static func planetName(_ p: Planet) -> String {
        switch p {
        case .mercury: "Mercury"; case .venus: "Venus"; case .mars: "Mars"; case .jupiter: "Jupiter"
        case .saturn: "Saturn"; case .uranus: "Uranus"; case .neptune: "Neptune"; case .pluto: "Pluto"
        }
    }

    private static func planetColor(_ p: Planet) -> Color {
        switch p {
        case .mercury: Color(white: 0.82)
        case .venus: Color(red: 1.0, green: 0.92, blue: 0.72)
        case .mars: Color(red: 1.0, green: 0.5, blue: 0.4)
        case .jupiter: Color(red: 1.0, green: 0.86, blue: 0.62)
        case .saturn: Color(red: 0.92, green: 0.82, blue: 0.55)
        case .uranus: Color(red: 0.6, green: 0.9, blue: 0.95)
        case .neptune: Color(red: 0.52, green: 0.66, blue: 1.0)
        case .pluto: Color(red: 0.82, green: 0.62, blue: 0.72)
        }
    }

    // MARK: Calibration

    private var calibrationTargetLabel: String {
        calibrationOptions.first { $0.id == calibrationTarget }?.label ?? calibrationTarget
    }

    private func startCalibration() {
        guard let latitude = provider.latitude, let longitude = provider.longitude else { return }
        let location = GeographicLocation(latitude: .degrees(latitude), longitude: .degrees(longitude))
        let jd = JulianDay(Date())
        func altitude(_ equatorial: EquatorialCoordinates) -> Double {
            CoordinateTransform.horizontal(equatorial, at: location, time: jd).altitude.degrees
        }

        var options: [CalibrationOption] = []
        let sunUp = altitude(Sun.position(at: jd)) > 0
        let moonUp = altitude(Moon.position(at: jd)) > 0
        options.append(CalibrationOption(id: "Sun", label: sunUp ? "Sun" : "Sun (below horizon)"))
        options.append(CalibrationOption(id: "Moon", label: moonUp ? "Moon" : "Moon (below horizon)"))
        if let star = brightestUpStar(location: location, jd: jd), let name = star.properName {
            options.append(CalibrationOption(id: name, label: name))
        }
        calibrationOptions = options
        calibrationTarget = sunUp ? "Sun" : (moonUp ? "Moon" : options.first?.id ?? "Sun")
        calibrating = true
    }

    private func brightestUpStar(location: GeographicLocation, jd: JulianDay) -> Star? {
        guard let catalog = store.catalog else { return nil }
        var best: Star?
        for star in catalog.stars where star.properName != nil {
            let altitude = CoordinateTransform.horizontal(star.equatorial, at: location, time: jd).altitude.degrees
            if altitude > 15, best == nil || star.apparentMagnitude < best!.apparentMagnitude { best = star }
        }
        return best
    }

    private func alignCalibration() {
        guard let latitude = provider.latitude, let longitude = provider.longitude,
              let frame = arController.currentFrame else { return }
        let location = GeographicLocation(latitude: .degrees(latitude), longitude: .degrees(longitude))
        let jd = JulianDay(Date())

        let trueAzimuth: Double
        switch calibrationTarget {
        case "Sun": trueAzimuth = CoordinateTransform.horizontal(Sun.position(at: jd), at: location, time: jd).azimuth.degrees
        case "Moon": trueAzimuth = CoordinateTransform.horizontal(Moon.position(at: jd), at: location, time: jd).azimuth.degrees
        default:
            guard let star = store.catalog?.star(named: calibrationTarget) else { return }
            trueAzimuth = CoordinateTransform.horizontal(star.equatorial, at: location, time: jd).azimuth.degrees
        }

        let columns = frame.camera.transform.columns.2
        let forward = SIMD3<Double>(-Double(columns.x), -Double(columns.y), -Double(columns.z)) // east, up, south
        let reportedAzimuth = atan2(forward.x, -forward.z) * 180 / .pi
        azimuthOffset = signedDelta(reportedAzimuth - trueAzimuth)
        manuallyCalibrated = true
        calibrating = false
    }

    /// Rotate the chrome (controls + Sun/Moon labels) to stay upright as the phone
    /// is tilted, snapping to the nearest 90°. The sky itself stays put.
    private func updateInterfaceRotation() {
        guard let gravity = provider.gravity else { return }
        let horizontal = (gravity.x * gravity.x + gravity.y * gravity.y).squareRoot()
        guard horizontal > 0.5 else { return }   // too flat to tell which way is down
        let degrees = atan2(gravity.x, -gravity.y) * 180 / .pi
        let target = -((degrees / 90).rounded() * 90)
        if abs(signedDelta(target - uiRotation)) > 1 {
            withAnimation(.spring(duration: 0.35)) { uiRotation = target }
        }
    }

    /// Until a manual Align, keep the AR heading roughly right by matching ARKit's
    /// (stable) heading to CoreMotion's compass-referenced heading.
    private func updateAutoCalibration() {
        guard mode == .ar, !manuallyCalibrated,
              let rotation = provider.rotationMatrix,
              let frame = arController.currentFrame else { return }
        let trueAzimuth = CameraBasis(rotation).pointing.azimuth.degrees
        let column = frame.camera.transform.columns.2
        let reportedAzimuth = atan2(-Double(column.x), Double(column.z)) * 180 / .pi
        let target = signedDelta(reportedAzimuth - trueAzimuth)
        if autoSeeded {
            azimuthOffset += 0.25 * signedDelta(target - azimuthOffset)   // gentle smoothing
        } else {
            azimuthOffset = target
            autoSeeded = true
        }
    }

    // MARK: Helpers

    private func labelMagnitudeLimit(_ fov: Double) -> Double {
        let t = max(0, min(1, (95 - fov) / (95 - 18)))
        return 1.6 + t * (5.0 - 1.6)
    }

    private func within(_ point: CGPoint, _ size: CGSize, margin: CGFloat) -> Bool {
        point.x > -margin && point.x < size.width + margin && point.y > -margin && point.y < size.height + margin
    }

    private func turnHint(_ body: ProjectedBody) -> String {
        let horizontal = body.deltaAzimuth >= 0 ? "→\(Int(body.deltaAzimuth.rounded()))°" : "←\(Int(abs(body.deltaAzimuth).rounded()))°"
        let vertical = body.deltaAltitude >= 0 ? "↑\(Int(body.deltaAltitude.rounded()))°" : "↓\(Int(abs(body.deltaAltitude).rounded()))°"
        return "\(horizontal) \(vertical)"
    }

    private var statusMessage: String {
        if mode == .ar && !ARCameraController.isSupported { return "AR isn't supported on this device." }
        if !provider.isAuthorized && provider.authorization != .notDetermined {
            return "Location access is off — enable it in Settings to map your sky."
        }
        if !provider.hasLocation { return "Finding your location…" }
        if mode == .ar { return "Starting camera…" }
        return "Calibrating compass — move the phone in a figure-8."
    }

    private func signedDelta(_ degrees: Double) -> Double {
        (degrees + 540).truncatingRemainder(dividingBy: 360) - 180
    }

    private func starRadius(_ magnitude: Double) -> Double { max(0.6, (6.6 - magnitude) * 0.45) }

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

    private func compass(_ azimuth: Angle) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((azimuth.degrees / 45.0).rounded()) % 8
        return points[(index + 8) % 8]
    }
}

private struct StarPoint: Identifiable {
    let id: Int
    let direction: SIMD3<Double>
    let magnitude: Double
    let color: Color
    let label: String?
}

private struct ConstellationPath: Identifiable {
    let id: String
    let polylines: [[SIMD3<Double>]]
    let labelDirection: SIMD3<Double>
}

/// A glyph placed on the sky by 3D direction — a zodiac sign or a planet.
private struct SkyGlyph {
    let direction: SIMD3<Double>
    let symbol: String
    let name: String
    let color: Color
}

private struct ProjectedBody: Identifiable {
    let id: String
    let name: String
    let color: Color
    let size: CGFloat
    let glow: CGFloat
    let azimuth: Angle
    let altitude: Angle
    let screen: CGPoint?
    let deltaAzimuth: Double
    let deltaAltitude: Double
}

private struct SolarState {
    let pointing: (azimuth: Angle, altitude: Angle)
    let bodies: [ProjectedBody]
}

private struct CalibrationOption: Identifiable {
    let id: String
    let label: String
}

private struct StarSelection {
    let title: String
    let subtitle: String
    let detail: String?

    init(star: Star) {
        title = star.properName ?? star.bayerFlamsteed ?? star.hipparcos.map { "HIP \($0)" } ?? "Star \(star.id)"
        var parts = [String(format: "mag %.1f", star.apparentMagnitude)]
        if let constellation = StarFacts.constellationName(star.constellation) ?? star.constellation {
            parts.append(constellation)
        }
        if let pc = star.distanceParsecs, pc > 0 {
            parts.append(String(format: "%.0f ly away", pc * Astrophysics.lightYearsPerParsec))
        }
        subtitle = parts.joined(separator: " · ")
        // A second line: the plain-language spectral kind, if we can read it.
        detail = StarFacts.spectralDescription(star.spectralType)
    }
}

#Preview {
    ContentView()
}
