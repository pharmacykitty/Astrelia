/// CelestialCore — the platform-agnostic astronomy engine for Astrolabe.
///
/// Pure computation only: no UIKit/SwiftUI, no sensors, no global mutable state.
/// Everything here is `Sendable` so it stays safe under Swift 6 strict concurrency,
/// and fully testable against published reference values (Meeus, JPL Horizons).
///
/// Phase 1 will fill this out: `Time` (Julian date, ΔT, sidereal time) and
/// `Coordinates` (equatorial ⇄ ecliptic ⇄ horizontal transforms).
public enum CelestialCore {
    /// Semantic version of the engine.
    public static let version = "0.0.1"
}
