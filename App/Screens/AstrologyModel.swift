import SwiftUI
import CoreLocation
import CelestialCore
import Astrology

/// Drives `AstrologyView`: fetches the observer's location and computes a live
/// chart of the current sky. Falls back to a sensible default location until
/// CoreLocation delivers (and so previews/simulator without a fix still render).
@MainActor
@Observable
final class AstrologyModel: NSObject, CLLocationManagerDelegate {
    private(set) var chart: NatalChart
    private(set) var locationLabel: String = "Default location · live sky"

    private let manager = CLLocationManager()
    /// Greenwich as a neutral default until a real fix arrives.
    private static let fallback = CLLocationCoordinate2D(latitude: 51.4779, longitude: -0.0015)

    override init() {
        chart = AstrologyModel.makeChart(at: AstrologyModel.fallback)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func start() async {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    /// Recompute the live chart for a coordinate at the current instant.
    static func makeChart(at coord: CLLocationCoordinate2D) -> NatalChart {
        let loc = GeographicLocation(
            latitude: .degrees(coord.latitude),
            longitude: .degrees(coord.longitude) // east-positive, matching CelestialCore
        )
        let settings = ChartSettings(
            houseSystem: .placidus,
            zodiac: .tropical,
            bodies: AstroBody.standard // Sun, Moon, Mercury–Pluto, nodes
        )
        return NatalChart(at: JulianDay(Date()), location: loc, settings: settings)
    }

    func position(_ body: AstroBody) -> BodyPosition? { chart.position(of: body) }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.last?.coordinate else { return }
        Task { @MainActor in
            self.chart = AstrologyModel.makeChart(at: coord)
            self.locationLabel = String(
                format: "%.2f°, %.2f° · live sky",
                coord.latitude, coord.longitude
            )
        }
    }
}
