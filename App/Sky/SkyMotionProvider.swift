import CoreLocation
import CoreMotion
import simd
import CelestialCore

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

    // Debug (`-snapshotSky [azimuth] [altitude]`, degrees): the simulator has no
    // compass or motion hardware, so the sky view sits at "Calibrating compass"
    // forever there. For marketing/screenshot runs this freezes the device
    // attitude at a fixed pointing (default: due south, 45° up) — production is
    // untouched (the arg is never present outside the harness).
    private static let snapshotPointing: (azimuth: Double, altitude: Double)? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-snapshotSky") else { return nil }
        let az = i + 1 < args.count ? Double(args[i + 1]) : nil
        let alt = i + 2 < args.count ? Double(args[i + 2]) : nil
        return (az ?? 180, alt ?? 45)
    }()

    /// Synthetic attitude for `-snapshotSky`: a portrait device whose back camera
    /// aims at the given azimuth/altitude, roll-free. Follows the convention
    /// `CameraBasis` documents (reference → device; device axes are the rows;
    /// world frame x = north, y = west, z = up; back camera looks along −Z).
    private static func snapshotMatrix(azimuth: Double, altitude: Double) -> CMRotationMatrix {
        let f = worldDirection(azimuth: .degrees(azimuth), altitude: .degrees(altitude))
        var u = SIMD3(0, 0, 1) - f * f.z              // world up, made ⊥ forward
        u = simd_length(u) < 1e-6 ? SIMD3(-f.z, 0, 0) : simd_normalize(u)
        let r = simd_normalize(simd_cross(f, u))      // screen-right (east when facing north)
        var m = CMRotationMatrix()
        m.m11 = r.x; m.m12 = r.y; m.m13 = r.z
        m.m21 = u.x; m.m22 = u.y; m.m23 = u.z
        m.m31 = -f.x; m.m32 = -f.y; m.m33 = -f.z
        return m
    }

    /// Latest device attitude as a rotation matrix (reference → device).
    var rotationMatrix: CMRotationMatrix? {
        if let p = Self.snapshotPointing {
            return Self.snapshotMatrix(azimuth: p.azimuth, altitude: p.altitude)
        }
        return motion.deviceMotion?.attitude.rotationMatrix
    }

    /// Gravity direction in the device frame — used to keep UI chrome upright as the
    /// phone is tilted. In portrait this is roughly (0, −1, 0).
    var gravity: (x: Double, y: Double, z: Double)? {
        if let p = Self.snapshotPointing {
            let m = Self.snapshotMatrix(azimuth: p.azimuth, altitude: p.altitude)
            return (-m.m13, -m.m23, -m.m33)           // R · (0, 0, −1), rows dotted with world −up
        }
        return motion.deviceMotion.map { ($0.gravity.x, $0.gravity.y, $0.gravity.z) }
    }

    var hasLocation: Bool { latitude != nil && longitude != nil }
    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    func start() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if let fixed = SnapshotLocation.coordinate {
            // Screenshot run: no prompt, no updates, just the given observer.
            latitude = fixed.latitude
            longitude = fixed.longitude
            authorization = .authorizedWhenInUse
        } else {
            locationManager.requestWhenInUseAuthorization()
            locationManager.startUpdatingLocation()
            authorization = locationManager.authorizationStatus
        }

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
        // A screenshot run stands in for an authorized observer; the real status
        // (never asked for) must not overwrite it and re-raise the prompt banner.
        guard SnapshotLocation.coordinate == nil else { return }
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorization = status }
    }
}
