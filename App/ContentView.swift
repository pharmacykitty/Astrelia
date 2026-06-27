import SwiftUI
import ARKit
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
    @State private var arController = ARCameraController()
    @State private var filters = SkyFilters()
    @State private var showFilters = false

    @State private var mode: SkyMode = .virtual
    @State private var starField: [StarPoint] = []          // sorted brightest-first
    @State private var constellationPaths: [ConstellationPath] = []

    @State private var fieldOfView = 65.0
    @State private var zoomAnchor = 65.0
    @State private var selection: StarSelection?

    // AR calibration (azimuth offset, degrees) that cancels compass error.
    @State private var azimuthOffset = 0.0
    @State private var calibrating = false
    @State private var calibrationOptions: [CalibrationOption] = []
    @State private var calibrationTarget = "Sun"

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                let camera = makeSkyCamera(size: geometry.size)
                let effectiveFOV = mode == .virtual ? fieldOfView : 55.0
                let state = camera.flatMap { solarState(camera: $0, size: geometry.size, date: timeline.date) }
                ZStack {
                    if mode == .ar {
                        ARCameraView(controller: arController).ignoresSafeArea()
                    } else {
                        background
                    }
                    if let camera {
                        skyCanvas(camera: camera, effectiveFOV: effectiveFOV, size: geometry.size)
                    }
                    if let state, filters.showSunMoon {
                        bodyNodes(state)
                    }
                    reticle
                    // Transparent hit layer for sky taps/zoom — sits BELOW the chrome
                    // so the mode toggle, filter button, etc. still receive their taps.
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(tapGesture(size: geometry.size))
                        .simultaneousGesture(zoomGesture)
                    chrome(state: state)
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .onAppear { provider.start(); store.loadIfNeeded() }
        .onDisappear { provider.stop(); arController.stop() }
        .onChange(of: mode) { _, newMode in
            if newMode == .ar { arController.start() } else { arController.stop() }
        }
        .onChange(of: filters) { _, _ in refreshSky() }
        .task {
            while !Task.isCancelled {
                refreshSky()
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
        .sheet(isPresented: $showFilters) {
            FilterSheet(filters: $filters, catalog: store.catalog)
                .presentationDetents([.medium, .large])
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

    private func chrome(state: SolarState?) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Text("Astrolabe")
                    .font(.system(.title2, design: .serif).weight(.bold))
                    .foregroundStyle(.white).shadow(radius: 3)
                HStack {
                    Picker("Mode", selection: $mode) {
                        Text("Sky").tag(SkyMode.virtual)
                        Text("AR").tag(SkyMode.ar)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                    Spacer()
                    Button { showFilters = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title3).foregroundStyle(.white)
                            .padding(10).background(.white.opacity(0.16), in: Circle())
                    }
                }
            }
            .padding(.top, 8)

            if let selection { selectionCard(selection) }
            if mode == .ar { calibrationBar() }

            Spacer()
            bottomPanel(state)
        }
        .padding()
    }

    private func selectionCard(_ selection: StarSelection) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selection.title).font(.headline).foregroundStyle(.white)
                Text(selection.subtitle).font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Button { self.selection = nil } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
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
                    Label(calibrationTargetLabel, systemImage: "scope").font(.subheadline)
                }
                Spacer()
                Button("Align") { alignCalibration() }.buttonStyle(.borderedProminent)
                Button("Cancel") { calibrating = false }.foregroundStyle(.white.opacity(0.7))
            }
            .padding(10).background(.ultraThinMaterial, in: Capsule())
        } else {
            HStack(spacing: 12) {
                Button { startCalibration() } label: {
                    Label("Calibrate", systemImage: "scope").font(.subheadline)
                }
                if azimuthOffset != 0 {
                    Text(String(format: "aligned %+.0f°", azimuthOffset))
                        .font(.caption).foregroundStyle(.green)
                    Button("Reset") { azimuthOffset = 0 }.font(.caption).foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(10).background(.ultraThinMaterial, in: Capsule())
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
                .font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.5))
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
            let direction = worldDirection(azimuth: horizon.azimuth, altitude: horizon.altitude)
            return ProjectedBody(
                id: name, name: name, color: color, size: size2, glow: glow,
                azimuth: horizon.azimuth, altitude: horizon.altitude,
                screen: camera.projectDirection(direction),
                deltaAzimuth: signedDelta(horizon.azimuth.degrees - pointing.azimuth.degrees),
                deltaAltitude: horizon.altitude.degrees - pointing.altitude.degrees
            )
        }

        return SolarState(pointing: pointing, bodies: [
            make("Sun", .orange, 24, 26, Sun.position(at: jd)),
            make("Moon", Color(white: 0.92), 20, 18, Moon.position(at: jd)),
        ])
    }

    private func refreshSky() {
        guard let latitude = provider.latitude, let longitude = provider.longitude else {
            if !starField.isEmpty { starField = [] }
            if !constellationPaths.isEmpty { constellationPaths = [] }
            return
        }
        let location = GeographicLocation(latitude: .degrees(latitude), longitude: .degrees(longitude))
        let jd = JulianDay(Date())

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
        calibrating = false
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

    init(star: Star) {
        title = star.properName ?? star.bayerFlamsteed ?? star.hipparcos.map { "HIP \($0)" } ?? "Star \(star.id)"
        var parts = [String(format: "mag %.1f", star.apparentMagnitude)]
        if let constellation = star.constellation { parts.append(constellation) }
        subtitle = parts.joined(separator: " · ")
    }
}

#Preview {
    ContentView()
}
