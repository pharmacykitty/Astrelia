import SwiftUI
import CelestialCore

/// Proof-of-life screen: drives the `CelestialCore` engine live, showing where the
/// Sun, Moon, and Sirius sit in the sky right now from a fixed location. (CoreLocation
/// and the real rendered sky arrive in later phases.)
struct ContentView: View {
    // Hard-coded observer for now — New York City.
    private let observer = GeographicLocation(latitude: .degrees(40.7128), longitude: .degrees(-74.0060))
    private let sirius = EquatorialCoordinates(
        rightAscension: .hours(6.752481),
        declination: .degrees(-16.716116)
    )

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            sky(at: JulianDay(context.date))
        }
    }

    private func sky(at jd: JulianDay) -> some View {
        let sun = CoordinateTransform.horizontal(Sun.position(at: jd), at: observer, time: jd)
        let moon = CoordinateTransform.horizontal(Moon.position(at: jd), at: observer, time: jd)
        let phase = Moon.phase(at: jd)
        let star = CoordinateTransform.horizontal(sirius, at: observer, time: jd)
        let litPercent = Int((phase.illuminatedFraction * 100).rounded())

        return ZStack {
            LinearGradient(
                colors: [Color(red: 0.02, green: 0.03, blue: 0.10), .black],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                VStack(spacing: 6) {
                    Text("Astrolabe")
                        .font(.system(size: 40, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                    Text("right now — from New York")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                }

                VStack(spacing: 20) {
                    row(symbol: "sun.max.fill", tint: .orange, name: "Sun", subtitle: nil, horizon: sun)
                    row(symbol: "moon.stars.fill", tint: .yellow, name: "Moon",
                        subtitle: "\(phase.name) · \(litPercent)% lit", horizon: moon)
                    row(symbol: "sparkle", tint: .white, name: "Sirius",
                        subtitle: "brightest star", horizon: star)
                }
                .padding(.horizontal, 20)
            }
            .padding()
        }
    }

    private func row(symbol: String, tint: Color, name: String, subtitle: String?, horizon: HorizontalCoordinates) -> some View {
        let isUp = horizon.altitude.degrees > 0
        return HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 32)
                .opacity(isUp ? 1 : 0.35)

            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline).foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.5))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "alt %+.1f°", horizon.altitude.degrees))
                    .foregroundStyle(isUp ? .white : .white.opacity(0.4))
                Text(String(format: "az %.0f°", horizon.azimuth.degrees))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .font(.subheadline.monospacedDigit())
        }
    }
}

#Preview {
    ContentView()
}
