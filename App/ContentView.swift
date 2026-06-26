import SwiftUI
import CoreMotion
import simd
import CelestialCore

// SwiftUI also declares `Angle`; in this file we always mean the astronomy one.
private typealias Angle = CelestialCore.Angle

/// The sky visualizer. Point the phone around and the real sky appears: the full
/// naked-eye star catalog drawn by brightness, the brightest stars labelled, and the
/// Sun & Moon as nodes. A filter sheet tunes what's shown; the bottom panel guides
/// you to the Sun & Moon (never the thousands of stars).
struct ContentView: View {
    @State private var provider = SkyMotionProvider()
    @State private var store = StarCatalogStore()
    @State private var filters = SkyFilters()
    @State private var showFilters = false
    @State private var starField: [StarPoint] = []

    private let verticalFOV = Angle.degrees(65)

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                let rotation = provider.rotationMatrix
                let state = rotation.flatMap { solarState(rotation: $0, size: geometry.size, date: timeline.date) }
                ZStack {
                    background
                    if let rotation {
                        let basis = CameraBasis(rotation)
                        starCanvas(rotation: rotation)
                        if filters.showStars && filters.showLabels {
                            starLabels(basis: basis, size: geometry.size)
                        }
                    }
                    if let state, filters.showSunMoon {
                        bodyNodes(state)
                    }
                    reticle
                    chrome(state: state)
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .onAppear { provider.start(); store.loadIfNeeded() }
        .onDisappear { provider.stop() }
        .onChange(of: filters) { _, _ in refreshStarField() }
        .task {
            while !Task.isCancelled {
                refreshStarField()
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
        .sheet(isPresented: $showFilters) {
            FilterSheet(filters: $filters, catalog: store.catalog)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Star field

    private func starCanvas(rotation: CMRotationMatrix) -> some View {
        Canvas { context, size in
            let basis = CameraBasis(rotation)
            let focal = Double(size.height) / 2 / tan(verticalFOV.radians / 2)
            let centerX = Double(size.width) / 2, centerY = Double(size.height) / 2
            for star in starField {
                let forward = simd_dot(star.direction, basis.forward)
                if forward <= 0.06 { continue }
                let x = centerX + simd_dot(star.direction, basis.right) / forward * focal
                let y = centerY - simd_dot(star.direction, basis.up) / forward * focal
                if x < -4 || x > Double(size.width) + 4 || y < -4 || y > Double(size.height) + 4 { continue }

                let radius = starRadius(star.magnitude)
                if star.magnitude < 1.5 {   // soft glow for the brightest
                    let g = radius * 3
                    context.fill(Path(ellipseIn: CGRect(x: x - g, y: y - g, width: g * 2, height: g * 2)),
                                 with: .color(star.color.opacity(0.18)))
                }
                context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(star.color))
            }
        }
    }

    private func starLabels(basis: CameraBasis, size: CGSize) -> some View {
        ForEach(starField.filter { $0.name != nil }) { star in
            if let point = projectToScreen(direction: star.direction, basis: basis,
                                           viewSize: size, verticalFOV: verticalFOV),
               isOnScreen(point, size: size) {
                Text(star.name ?? "")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .position(x: point.x, y: point.y + 12)
            }
        }
    }

    // MARK: Sun & Moon

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
        VStack {
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

            Spacer()
            bottomPanel(state)
        }
        .padding()
    }

    @ViewBuilder
    private func bottomPanel(_ state: SolarState?) -> some View {
        VStack(spacing: 10) {
            if let state {
                if filters.showSunMoon {
                    ForEach(state.bodies) { body in
                        bodyRow(body)
                    }
                    Divider().overlay(.white.opacity(0.2))
                }
                Text(String(format: "Pointing  %@ %.0f°  ·  alt %+.0f°",
                            compass(state.pointing.azimuth),
                            state.pointing.azimuth.degrees,
                            state.pointing.altitude.degrees))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                Text(statusMessage)
                    .font(.callout)
                    .multilineTextAlignment(.center)
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
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
            Text(inView ? "● here" : turnHint(body))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(inView ? .green : .white.opacity(0.85))
                .frame(width: 92, alignment: .trailing)
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
            let screen = projectToScreen(direction: direction, basis: basis,
                                         viewSize: size, verticalFOV: verticalFOV)
            return ProjectedBody(
                id: name, name: name, color: color, size: size2, glow: glow,
                azimuth: horizon.azimuth, altitude: horizon.altitude, screen: screen,
                deltaAzimuth: signedDelta(horizon.azimuth.degrees - pointing.azimuth.degrees),
                deltaAltitude: horizon.altitude.degrees - pointing.altitude.degrees
            )
        }

        return SolarState(
            pointing: pointing,
            bodies: [
                make("Sun", .orange, 24, 26, Sun.position(at: jd)),
                make("Moon", Color(white: 0.92), 20, 18, Moon.position(at: jd)),
            ]
        )
    }

    private func refreshStarField() {
        guard filters.showStars,
              let catalog = store.catalog,
              let latitude = provider.latitude, let longitude = provider.longitude else {
            if !starField.isEmpty { starField = [] }
            return
        }
        let location = GeographicLocation(latitude: .degrees(latitude), longitude: .degrees(longitude))
        let jd = JulianDay(Date())
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
                name: star.apparentMagnitude <= 1.6 ? star.properName : nil
            ))
        }
        starField = points
    }

    // MARK: Helpers

    private func turnHint(_ body: ProjectedBody) -> String {
        let horizontal = body.deltaAzimuth >= 0
            ? "→\(Int(body.deltaAzimuth.rounded()))°"
            : "←\(Int(abs(body.deltaAzimuth).rounded()))°"
        let vertical = body.deltaAltitude >= 0
            ? "↑\(Int(body.deltaAltitude.rounded()))°"
            : "↓\(Int(abs(body.deltaAltitude).rounded()))°"
        return "\(horizontal) \(vertical)"
    }

    private var statusMessage: String {
        if !provider.isAuthorized && provider.authorization != .notDetermined {
            return "Location access is off — enable it in Settings to map your sky."
        }
        if !provider.hasLocation { return "Finding your location…" }
        return "Calibrating compass — move the phone in a figure-8."
    }

    private func isOnScreen(_ point: CGPoint, size: CGSize) -> Bool {
        point.x > -80 && point.x < size.width + 80 && point.y > -80 && point.y < size.height + 80
    }

    private func signedDelta(_ degrees: Double) -> Double {
        (degrees + 540).truncatingRemainder(dividingBy: 360) - 180
    }

    private func starRadius(_ magnitude: Double) -> Double {
        max(0.6, (6.6 - magnitude) * 0.45)
    }

    private func starColor(_ colorIndex: Double?) -> Color {
        guard let ci = colorIndex else { return .white }
        switch ci {
        case ..<0.0: return Color(red: 0.70, green: 0.80, blue: 1.0)   // blue-white
        case ..<0.3: return Color(red: 0.86, green: 0.91, blue: 1.0)   // white
        case ..<0.6: return .white
        case ..<1.0: return Color(red: 1.0, green: 0.95, blue: 0.84)   // yellow-white
        case ..<1.5: return Color(red: 1.0, green: 0.85, blue: 0.65)   // orange
        default:     return Color(red: 1.0, green: 0.76, blue: 0.60)   // reddish
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
    let name: String?
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

#Preview {
    ContentView()
}
