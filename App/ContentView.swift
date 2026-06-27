import SwiftUI
import CoreMotion
import simd
import CelestialCore

// SwiftUI also declares `Angle`; in this file we always mean the astronomy one.
private typealias Angle = CelestialCore.Angle

/// The sky visualizer. Point the phone around for the real sky: the naked-eye star
/// catalog drawn by brightness, constellation figures, and the Sun & Moon as nodes.
/// Pinch to zoom (more star names reveal as you do), tap a star to identify it, and
/// use the filter sheet to tune what's shown.
struct ContentView: View {
    @State private var provider = SkyMotionProvider()
    @State private var store = StarCatalogStore()
    @State private var filters = SkyFilters()
    @State private var showFilters = false

    @State private var starField: [StarPoint] = []          // sorted brightest-first
    @State private var constellationPaths: [ConstellationPath] = []

    @State private var fieldOfView = 65.0
    @State private var zoomAnchor = 65.0
    @State private var selection: StarSelection?

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                let rotation = provider.rotationMatrix
                let state = rotation.flatMap { solarState(rotation: $0, size: geometry.size, date: timeline.date) }
                ZStack {
                    background
                    if let rotation {
                        skyCanvas(rotation: rotation, size: geometry.size)
                    }
                    if let state, filters.showSunMoon {
                        bodyNodes(state)
                    }
                    reticle
                    chrome(state: state)
                }
                .gesture(tapGesture(size: geometry.size))
                .simultaneousGesture(zoomGesture)
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .onAppear { provider.start(); store.loadIfNeeded() }
        .onDisappear { provider.stop() }
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

    private func skyCanvas(rotation: CMRotationMatrix, size: CGSize) -> some View {
        let basis = CameraBasis(rotation)
        let focal = Double(size.height) / 2 / tan(Angle.degrees(fieldOfView).radians / 2)
        let centerX = Double(size.width) / 2, centerY = Double(size.height) / 2
        let labelLimit = labelMagnitudeLimit(fieldOfView)

        func project(_ direction: SIMD3<Double>, minForward: Double = 0.06) -> CGPoint? {
            let forward = simd_dot(direction, basis.forward)
            guard forward > minForward else { return nil }
            return CGPoint(x: centerX + simd_dot(direction, basis.right) / forward * focal,
                           y: centerY - simd_dot(direction, basis.up) / forward * focal)
        }

        return Canvas { context, _ in
            // Constellation lines.
            if filters.showConstellations {
                let stroke = GraphicsContext.Shading.color(Color(red: 0.45, green: 0.6, blue: 1.0).opacity(0.32))
                for path in constellationPaths {
                    var shape = Path()
                    for line in path.polylines {
                        var previous: CGPoint?
                        for vertex in line {
                            if let point = project(vertex, minForward: 0.15) {
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
                guard let point = project(star.direction) else { continue }
                if point.x < -4 || point.x > size.width + 4 || point.y < -4 || point.y > size.height + 4 { continue }
                let radius = starRadius(star.magnitude)
                if star.magnitude < 1.5 {
                    let g = radius * 3
                    context.fill(Path(ellipseIn: CGRect(x: point.x - g, y: point.y - g, width: g * 2, height: g * 2)),
                                 with: .color(star.color.opacity(0.18)))
                }
                context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(star.color))
            }

            // Labels (constellation names first, then stars by brightness), de-cluttered.
            var occupied: [CGRect] = []
            func place(_ text: Text, at point: CGPoint, below: Bool) {
                let resolved = context.resolve(text)
                let measured = resolved.measure(in: CGSize(width: 200, height: 60))
                let origin = CGPoint(x: point.x, y: point.y + (below ? 9 : 0))
                let rect = CGRect(x: origin.x - measured.width / 2, y: origin.y - measured.height / 2,
                                  width: measured.width, height: measured.height)
                guard rect.minX > 0, rect.maxX < size.width, rect.minY > 40, rect.maxY < size.height - 120 else { return }
                if occupied.contains(where: { $0.intersects(rect) }) { return }
                occupied.append(rect.insetBy(dx: -4, dy: -4))
                context.draw(resolved, at: origin)
            }

            if filters.showConstellations {
                for path in constellationPaths {
                    if let point = project(path.labelDirection, minForward: 0.25) {
                        place(Text(path.id.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(red: 0.6, green: 0.72, blue: 1.0).opacity(0.55)),
                              at: point, below: false)
                    }
                }
            }
            if filters.showLabels {
                for star in starField where star.label != nil && star.magnitude <= labelLimit {
                    guard let point = project(star.direction) else { continue }
                    place(Text(star.label ?? "")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82)),
                          at: point, below: true)
                }
            }
        }
    }

    // MARK: Sun & Moon nodes

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
        Circle().stroke(.white.opacity(0.22), lineWidth: 1).frame(width: 44, height: 44)
    }

    private func chrome(state: SolarState?) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Text("Astrolabe")
                    .font(.system(.title2, design: .serif).weight(.bold))
                    .foregroundStyle(.white)
                HStack {
                    Spacer()
                    Button { showFilters = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                }
            }
            .padding(.top, 8)

            if let selection { selectionCard(selection) }

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
    private func bottomPanel(_ state: SolarState?) -> some View {
        VStack(spacing: 10) {
            if let state {
                if filters.showSunMoon {
                    ForEach(state.bodies) { body in bodyRow(body) }
                    Divider().overlay(.white.opacity(0.2))
                }
                Text(String(format: "Pointing  %@ %.0f°  ·  alt %+.0f°  ·  %.0f° fov",
                            compass(state.pointing.azimuth),
                            state.pointing.azimuth.degrees,
                            state.pointing.altitude.degrees, fieldOfView))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                Text(statusMessage)
                    .font(.callout).multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.8))
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
            .onChanged { value in fieldOfView = min(95, max(18, zoomAnchor / value)) }
            .onEnded { _ in zoomAnchor = fieldOfView }
    }

    private func tapGesture(size: CGSize) -> some Gesture {
        SpatialTapGesture()
            .onEnded { event in identify(at: event.location, size: size) }
    }

    private func identify(at location: CGPoint, size: CGSize) {
        guard let rotation = provider.rotationMatrix, let catalog = store.catalog else { return }
        let basis = CameraBasis(rotation)
        var best: (distance: CGFloat, id: Int)?
        for star in starField {
            guard let point = projectToScreen(direction: star.direction, basis: basis,
                                              viewSize: size, verticalFOV: .degrees(fieldOfView)) else { continue }
            let distance = hypot(point.x - location.x, point.y - location.y)
            if distance < 30, best == nil || distance < best!.distance {
                best = (distance, star.id)
            }
        }
        if let best, let star = catalog.star(id: best.id) {
            selection = StarSelection(star: star)
        } else {
            selection = nil
        }
    }

    // MARK: Building state

    private func solarState(rotation: CMRotationMatrix, size: CGSize, date: Date) -> SolarState? {
        guard let latitude = provider.latitude, let longitude = provider.longitude else { return nil }
        let basis = CameraBasis(rotation)
        let pointing = basis.pointing
        let location = GeographicLocation(latitude: .degrees(latitude), longitude: .degrees(longitude))
        let jd = JulianDay(date)

        func make(_ name: String, _ color: Color, _ size2: CGFloat, _ glow: CGFloat,
                  _ equatorial: EquatorialCoordinates) -> ProjectedBody {
            let horizon = CoordinateTransform.horizontal(equatorial, at: location, time: jd)
            let direction = worldDirection(azimuth: horizon.azimuth, altitude: horizon.altitude)
            return ProjectedBody(
                id: name, name: name, color: color, size: size2, glow: glow,
                azimuth: horizon.azimuth, altitude: horizon.altitude,
                screen: projectToScreen(direction: direction, basis: basis, viewSize: size, verticalFOV: .degrees(fieldOfView)),
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

        // Stars
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
                    label: star.properName ?? star.bayerFlamsteed
                ))
            }
            points.sort { $0.magnitude < $1.magnitude }
            starField = points
        } else if !starField.isEmpty {
            starField = []
        }

        // Constellations
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

    // MARK: Helpers

    private func labelMagnitudeLimit(_ fov: Double) -> Double {
        let t = max(0, min(1, (95 - fov) / (95 - 18)))   // 0 wide, 1 zoomed-in
        return 1.6 + t * (5.0 - 1.6)
    }

    private func turnHint(_ body: ProjectedBody) -> String {
        let horizontal = body.deltaAzimuth >= 0 ? "→\(Int(body.deltaAzimuth.rounded()))°" : "←\(Int(abs(body.deltaAzimuth).rounded()))°"
        let vertical = body.deltaAltitude >= 0 ? "↑\(Int(body.deltaAltitude.rounded()))°" : "↓\(Int(abs(body.deltaAltitude).rounded()))°"
        return "\(horizontal) \(vertical)"
    }

    private var statusMessage: String {
        if !provider.isAuthorized && provider.authorization != .notDetermined {
            return "Location access is off — enable it in Settings to map your sky."
        }
        if !provider.hasLocation { return "Finding your location…" }
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

private struct StarSelection {
    let title: String
    let subtitle: String

    init(star: Star) {
        title = star.properName ?? star.bayerFlamsteed ?? star.hipparcos.map { "HIP \($0)" } ?? "Star \(star.id)"
        var parts: [String] = [String(format: "mag %.1f", star.apparentMagnitude)]
        if let constellation = star.constellation { parts.append(constellation) }
        if let spectral = star.spectralType { parts.append(spectral) }
        subtitle = parts.joined(separator: " · ")
    }
}

#Preview {
    ContentView()
}
