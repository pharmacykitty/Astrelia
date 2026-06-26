import SwiftUI
import CelestialCore

// SwiftUI also declares `Angle`; in this file we always mean the astronomy one.
private typealias Angle = CelestialCore.Angle

/// The sky visualizer: point the phone around and the Sun, Moon, and Sirius appear
/// as nodes where they actually are in the sky, computed live from your location,
/// the current time, and the phone's orientation. A bottom panel lists each body's
/// real azimuth/altitude and a turn-guide arrow toward it (also our calibration aid).
struct ContentView: View {
    @State private var provider = SkyMotionProvider()

    private let sirius = EquatorialCoordinates(
        rightAscension: .hours(6.752481),
        declination: .degrees(-16.716116)
    )
    private let verticalFOV = Angle.degrees(65)

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                let state = currentState(size: geometry.size, date: timeline.date)
                ZStack {
                    background
                    if let state {
                        ForEach(state.bodies) { item in
                            if let point = item.screen, isOnScreen(point, size: geometry.size) {
                                node(item.body).position(point)
                            }
                        }
                    }
                    reticle
                    VStack {
                        topHint
                        Spacer()
                        panel(state)
                    }
                    .padding()
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .onAppear { provider.start() }
        .onDisappear { provider.stop() }
    }

    // MARK: Computed state

    private func currentState(size: CGSize, date: Date) -> SkyState? {
        guard let latitude = provider.latitude,
              let longitude = provider.longitude,
              let rotation = provider.rotationMatrix else { return nil }

        let basis = CameraBasis(rotation)
        let pointing = basis.pointing
        let projected = bodies(latitude: latitude, longitude: longitude, date: date).map { body -> ProjectedBody in
            let direction = worldDirection(azimuth: body.azimuth, altitude: body.altitude)
            let screen = projectToScreen(direction: direction, basis: basis,
                                         viewSize: size, verticalFOV: verticalFOV)
            let deltaAzimuth = signedDelta(body.azimuth.degrees - pointing.azimuth.degrees)
            let deltaAltitude = body.altitude.degrees - pointing.altitude.degrees
            return ProjectedBody(id: body.id, body: body, screen: screen,
                                 deltaAzimuth: deltaAzimuth, deltaAltitude: deltaAltitude)
        }
        return SkyState(pointing: pointing, bodies: projected)
    }

    // MARK: Sky node

    private func node(_ body: SkyBody) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(body.color)
                .frame(width: body.size, height: body.size)
                .shadow(color: body.color.opacity(0.9), radius: body.glow)
                .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 0.5))
            Text(body.name).font(.caption.weight(.semibold)).foregroundStyle(.white)
        }
        .shadow(radius: 2)
    }

    // MARK: Chrome

    private var background: some View {
        LinearGradient(colors: [Color(red: 0.02, green: 0.03, blue: 0.12), .black],
                       startPoint: .top, endPoint: .bottom)
    }

    private var reticle: some View {
        Circle().stroke(.white.opacity(0.25), lineWidth: 1).frame(width: 44, height: 44)
    }

    private var topHint: some View {
        Text("Astrolabe")
            .font(.system(.title2, design: .serif).weight(.bold))
            .foregroundStyle(.white)
            .padding(.top, 8)
    }

    @ViewBuilder
    private func panel(_ state: SkyState?) -> some View {
        VStack(spacing: 10) {
            if let state {
                ForEach(state.bodies) { item in
                    bodyRow(item)
                }
                Divider().overlay(.white.opacity(0.2))
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

    private func bodyRow(_ item: ProjectedBody) -> some View {
        let inView = abs(item.deltaAzimuth) < 12 && abs(item.deltaAltitude) < 12
        return HStack(spacing: 10) {
            Circle().fill(item.body.color).frame(width: 9, height: 9)
            Text(item.body.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            Spacer()
            Text(String(format: "az %.0f° alt %+.0f°", item.body.azimuth.degrees, item.body.altitude.degrees))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
            Text(inView ? "● here" : turnHint(item))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(inView ? .green : .white.opacity(0.85))
                .frame(width: 96, alignment: .trailing)
        }
    }

    // MARK: Helpers

    private func turnHint(_ item: ProjectedBody) -> String {
        let horizontal = item.deltaAzimuth >= 0
            ? "→\(Int(item.deltaAzimuth.rounded()))°"
            : "←\(Int(abs(item.deltaAzimuth).rounded()))°"
        let vertical = item.deltaAltitude >= 0
            ? "↑\(Int(item.deltaAltitude.rounded()))°"
            : "↓\(Int(abs(item.deltaAltitude).rounded()))°"
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

    private func bodies(latitude: Double, longitude: Double, date: Date) -> [SkyBody] {
        let location = GeographicLocation(latitude: .degrees(latitude), longitude: .degrees(longitude))
        let jd = JulianDay(date)
        func horizon(_ equatorial: EquatorialCoordinates) -> HorizontalCoordinates {
            CoordinateTransform.horizontal(equatorial, at: location, time: jd)
        }

        let sun = horizon(Sun.position(at: jd))
        let moon = horizon(Moon.position(at: jd))
        let star = horizon(sirius)

        return [
            SkyBody(id: "sun", name: "Sun", color: .orange, size: 24, glow: 26,
                    azimuth: sun.azimuth, altitude: sun.altitude),
            SkyBody(id: "moon", name: "Moon", color: Color(white: 0.92), size: 20, glow: 18,
                    azimuth: moon.azimuth, altitude: moon.altitude),
            SkyBody(id: "sirius", name: "Sirius", color: Color(red: 0.72, green: 0.82, blue: 1.0),
                    size: 12, glow: 10, azimuth: star.azimuth, altitude: star.altitude),
        ]
    }

    private func compass(_ azimuth: Angle) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((azimuth.degrees / 45.0).rounded()) % 8
        return points[(index + 8) % 8]
    }
}

private struct SkyBody: Identifiable {
    let id: String
    let name: String
    let color: Color
    let size: CGFloat
    let glow: CGFloat
    let azimuth: Angle
    let altitude: Angle
}

private struct ProjectedBody: Identifiable {
    let id: String
    let body: SkyBody
    let screen: CGPoint?
    let deltaAzimuth: Double     // degrees: + = turn right
    let deltaAltitude: Double    // degrees: + = tilt up
}

private struct SkyState {
    let pointing: (azimuth: Angle, altitude: Angle)
    let bodies: [ProjectedBody]
}

#Preview {
    ContentView()
}
