/// CelestialCore — the platform-agnostic astronomy engine for Astrolabe.
///
/// Pure computation only: no UIKit/SwiftUI, no sensors, no global mutable state.
/// Everything here is `Sendable` so it stays safe under Swift 6 strict concurrency,
/// and fully testable against published reference values (Meeus, JPL Horizons).
///
/// (Named `…Info` rather than `CelestialCore` so it doesn't collide with the
/// module name — `CelestialCore.Angle` should always mean the module's type.)
public enum CelestialCoreInfo {
    /// Semantic version of the engine.
    public static let version = "0.0.1"
}
