import SwiftUI
import CelestialCore

/// Proof-of-life screen: drives the Phase-1 `CelestialCore` math live, showing
/// where Sirius sits in the sky right now from a fixed location. (CoreLocation and
/// the real rendered sky arrive in later phases.)
struct ContentView: View {
    // Hard-coded observer for now — New York City.
    private let observer = GeographicLocation(latitude: .degrees(40.7128), longitude: .degrees(-74.0060))
    private let sirius = EquatorialCoordinates(
        rightAscension: .hours(6.752481),
        declination: .degrees(-16.716116)
    )

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let horizon = CoordinateTransform.horizontal(sirius, at: observer, time: JulianDay(context.date))
            sky(horizon)
        }
    }

    private func sky(_ horizon: HorizontalCoordinates) -> some View {
        let isUp = horizon.altitude.degrees > 0
        return ZStack {
            LinearGradient(
                colors: [Color(red: 0.02, green: 0.03, blue: 0.10), .black],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Text("Astrolabe")
                    .font(.system(size: 44, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                Text("Sirius, right now — from New York")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))

                readout("Altitude", String(format: "%+.1f°", horizon.altitude.degrees))
                readout("Azimuth", String(format: "%.1f°", horizon.azimuth.degrees))

                Text(isUp ? "above the horizon ✦" : "below the horizon ☾")
                    .font(.headline)
                    .foregroundStyle(isUp ? .yellow : .white.opacity(0.4))
                    .padding(.top, 4)
            }
        }
    }

    private func readout(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.white)
        }
        .font(.title3)
        .padding(.horizontal, 48)
    }
}

#Preview {
    ContentView()
}
