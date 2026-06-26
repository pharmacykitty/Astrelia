import SwiftUI
import CelestialCore

// SwiftUI also declares `Angle`; in this file we always mean the astronomy one.
private typealias Angle = CelestialCore.Angle

/// The sky visualizer: point the phone around and the Sun, Moon, and Sirius appear
/// as nodes where they actually are in the sky, computed live from your location,
/// the current time, and the phone's orientation.
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
                ZStack {
                    background
                    nodes(in: geometry.size, date: timeline.date)
                    reticle
                    overlay
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .onAppear { provider.start() }
        .onDisappear { provider.stop() }
    }

    // MARK: Sky nodes

    @ViewBuilder
    private func nodes(in size: CGSize, date: Date) -> some View {
        if let latitude = provider.latitude,
           let longitude = provider.longitude,
           let rotation = provider.rotationMatrix {
            let basis = CameraBasis(rotation)
            ForEach(bodies(latitude: latitude, longitude: longitude, date: date)) { body in
                if let point = projectToScreen(
                    direction: worldDirection(azimuth: body.azimuth, altitude: body.altitude),
                    basis: basis, viewSize: size, verticalFOV: verticalFOV
                ), isOnScreen(point, size: size) {
                    node(body).position(point)
                }
            }
        }
    }

    private func node(_ body: SkyBody) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(body.color)
                .frame(width: body.size, height: body.size)
                .shadow(color: body.color.opacity(0.9), radius: body.glow)
                .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 0.5))
            Text(body.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            Text(body.detail)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.6))
        }
        .shadow(radius: 2)
    }

    // MARK: Chrome

    private var background: some View {
        LinearGradient(
            colors: [Color(red: 0.02, green: 0.03, blue: 0.12), .black],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var reticle: some View {
        Circle()
            .stroke(.white.opacity(0.25), lineWidth: 1)
            .frame(width: 44, height: 44)
    }

    @ViewBuilder
    private var overlay: some View {
        VStack {
            topHint
            Spacer()
            statusPanel
        }
        .padding()
    }

    private var topHint: some View {
        Text("Astrolabe")
            .font(.system(.title2, design: .serif).weight(.bold))
            .foregroundStyle(.white)
            .padding(.top, 8)
    }

    @ViewBuilder
    private var statusPanel: some View {
        VStack(spacing: 8) {
            if !provider.isAuthorized && provider.authorization != .notDetermined {
                label("Location access is off — enable it in Settings to map your sky.")
            } else if !provider.hasLocation {
                label("Finding your location…")
            } else if provider.rotationMatrix == nil {
                label("Calibrating compass — move the phone in a figure-8.")
            } else if let rotation = provider.rotationMatrix {
                let pointing = CameraBasis(rotation).pointing
                label(String(format: "Pointing  %@ %.0f°  ·  alt %+.0f°",
                             compass(pointing.azimuth), pointing.azimuth.degrees, pointing.altitude.degrees))
                Text("Point the phone around to find the Sun, Moon & Sirius")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.bottom, 6)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.callout.monospacedDigit())
            .multilineTextAlignment(.center)
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.white.opacity(0.08), in: Capsule())
    }

    // MARK: Helpers

    private func isOnScreen(_ point: CGPoint, size: CGSize) -> Bool {
        point.x > -80 && point.x < size.width + 80 && point.y > -80 && point.y < size.height + 80
    }

    private func bodies(latitude: Double, longitude: Double, date: Date) -> [SkyBody] {
        let location = GeographicLocation(latitude: .degrees(latitude), longitude: .degrees(longitude))
        let jd = JulianDay(date)
        func horizon(_ equatorial: EquatorialCoordinates) -> HorizontalCoordinates {
            CoordinateTransform.horizontal(equatorial, at: location, time: jd)
        }

        let sun = horizon(Sun.position(at: jd))
        let moon = horizon(Moon.position(at: jd))
        let phase = Moon.phase(at: jd)
        let star = horizon(sirius)
        let lit = Int((phase.illuminatedFraction * 100).rounded())

        return [
            SkyBody(id: "sun", name: "Sun", detail: format(sun),
                    color: .orange, size: 24, glow: 26, azimuth: sun.azimuth, altitude: sun.altitude),
            SkyBody(id: "moon", name: "Moon", detail: "\(lit)% · " + format(moon),
                    color: Color(white: 0.92), size: 20, glow: 18, azimuth: moon.azimuth, altitude: moon.altitude),
            SkyBody(id: "sirius", name: "Sirius", detail: format(star),
                    color: Color(red: 0.72, green: 0.82, blue: 1.0), size: 12, glow: 10,
                    azimuth: star.azimuth, altitude: star.altitude),
        ]
    }

    private func format(_ horizon: HorizontalCoordinates) -> String {
        String(format: "alt %+.0f°", horizon.altitude.degrees)
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
    let detail: String
    let color: Color
    let size: CGFloat
    let glow: CGFloat
    let azimuth: Angle
    let altitude: Angle
}

#Preview {
    ContentView()
}
