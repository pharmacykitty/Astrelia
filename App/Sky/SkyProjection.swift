import CoreGraphics
import CoreMotion
import simd
import CelestialCore

/// The camera (device) axes expressed in the world reference frame
/// (X = true north, Y = west, Z = up — the `.xTrueNorthZVertical` frame).
///
/// CoreMotion's rotation matrix maps reference-frame vectors into the device frame
/// (verified on-device), so the device axes are the *rows* of that matrix. The back
/// camera — what you aim at the sky — looks along −Z of the device.
struct CameraBasis {
    let right: SIMD3<Double>     // screen → right
    let up: SIMD3<Double>        // screen → top
    let forward: SIMD3<Double>   // back camera look direction

    init(_ m: CMRotationMatrix) {
        right = SIMD3(m.m11, m.m12, m.m13)
        up = SIMD3(m.m21, m.m22, m.m23)
        forward = SIMD3(-m.m31, -m.m32, -m.m33)
    }

    /// Where the back camera is currently aimed, in horizontal coordinates.
    var pointing: (azimuth: Angle, altitude: Angle) {
        // World frame: x = north, y = west, z = up. East = −y.
        let azimuth = Angle.atan2(y: -forward.y, x: forward.x).normalized
        let altitude = Angle.asin(min(1, max(-1, forward.z)))
        return (azimuth, altitude)
    }
}

/// Unit vector toward a body in the world reference frame (north, west, up).
func worldDirection(azimuth: Angle, altitude: Angle) -> SIMD3<Double> {
    let horizontal = altitude.cosine
    return SIMD3(
        horizontal * azimuth.cosine,    // north
        -horizontal * azimuth.sine,     // west  (= −east)
        altitude.sine                   // up
    )
}

/// Gnomonic projection of a world direction onto the screen, given the camera basis
/// and a vertical field of view. Returns `nil` when the point is behind the camera.
func projectToScreen(
    direction: SIMD3<Double>,
    basis: CameraBasis,
    viewSize: CGSize,
    verticalFOV: Angle
) -> CGPoint? {
    let forward = simd_dot(direction, basis.forward)
    guard forward > 0.06 else { return nil }   // behind / at the very edge

    let rightward = simd_dot(direction, basis.right)
    let upward = simd_dot(direction, basis.up)

    let focalLength = Double(viewSize.height) / 2.0 / tan(verticalFOV.radians / 2.0)
    let x = Double(viewSize.width) / 2.0 + (rightward / forward) * focalLength
    let y = Double(viewSize.height) / 2.0 - (upward / forward) * focalLength
    return CGPoint(x: x, y: y)
}
