import CoreLocation
import CoreMotion

/// Fuses the two sensors the sky view needs: where you are (CoreLocation) and where
/// the phone is pointed (CoreMotion device attitude, referenced to true north).
///
/// Device motion is read in a "pull" style — we start updates and read the latest
/// `deviceMotion` once per display frame from the view — so there's no background
/// queue or cross-actor hand-off for the high-rate orientation data.
@MainActor
@Observable
final class SkyMotionProvider: NSObject, CLLocationManagerDelegate {
    private let motion = CMMotionManager()
    private let locationManager = CLLocationManager()

    var latitude: Double?
    var longitude: Double?
    var authorization: CLAuthorizationStatus = .notDetermined

    nonisolated override init() { super.init() }

    /// `true` once the device motion reference frame has locked onto true north.
    var isPointingReady: Bool { motion.deviceMotion?.attitude != nil }

    /// Latest device attitude as a rotation matrix (reference → device).
    var rotationMatrix: CMRotationMatrix? { motion.deviceMotion?.attitude.rotationMatrix }

    var hasLocation: Bool { latitude != nil && longitude != nil }
    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    func start() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        authorization = locationManager.authorizationStatus

        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 60.0
            // True north requires location services, which we've just started.
            motion.startDeviceMotionUpdates(using: .xTrueNorthZVertical)
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        locationManager.stopUpdatingLocation()
    }

    // MARK: CLLocationManagerDelegate (delivered off the main actor)

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in
            if let coordinate {
                self.latitude = coordinate.latitude
                self.longitude = coordinate.longitude
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorization = status }
    }
}
