import CoreLocation
import CelestialCore

/// A minimal one-shot location source for screens that need the observer's place but
/// not the full motion/heading stack (e.g. the Tonight feed). Mirrors the permission
/// flow of `SkyMotionProvider` but without CoreMotion.
@MainActor
@Observable
final class ObserverLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var latitude: Double?
    var longitude: Double?
    var authorization: CLAuthorizationStatus = .notDetermined

    var location: GeographicLocation? {
        guard let latitude, let longitude else { return nil }
        return GeographicLocation(latitude: .degrees(latitude), longitude: .degrees(longitude))
    }

    var denied: Bool { authorization == .denied || authorization == .restricted }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer   // city-level is plenty
        authorization = manager.authorizationStatus
    }

    func start() {
        if let fixed = SnapshotLocation.coordinate {
            latitude = fixed.latitude
            longitude = fixed.longitude
            authorization = .authorizedWhenInUse
            return
        }
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() { manager.stopUpdatingLocation() }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in
            self.latitude = coordinate.latitude
            self.longitude = coordinate.longitude
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard SnapshotLocation.coordinate == nil else { return }
        // `start()` already called startUpdatingLocation; iOS begins delivering once
        // authorised, so we only need to mirror the status here.
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorization = status }
    }
}
