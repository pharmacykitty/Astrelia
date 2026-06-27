import CoreGraphics
import CoreMotion
import simd
import ARKit
import UIKit
import CelestialCore

/// A unified projector for the sky overlay. Both the no-camera "Sky" mode and the
/// ARKit camera mode produce one of these per frame, so the star/constellation/label
/// rendering is identical regardless of how we know where the phone points.
///
/// Input directions are unit vectors in the CoreMotion reference frame
/// (x = north, y = west, z = up) — the same vectors `worldDirection(azimuth:altitude:)`
/// already produces.
struct SkyCamera {
    let projectDirection: (SIMD3<Double>) -> CGPoint?
    let pointing: (azimuth: Angle, altitude: Angle)

    /// No-camera mode: gnomonic projection straight from the CoreMotion attitude.
    static func motion(rotation: CMRotationMatrix, fieldOfView: Angle, size: CGSize) -> SkyCamera {
        let basis = CameraBasis(rotation)
        let focal = Double(size.height) / 2 / tan(fieldOfView.radians / 2)
        let centerX = Double(size.width) / 2, centerY = Double(size.height) / 2
        return SkyCamera(
            projectDirection: { direction in
                let forward = simd_dot(direction, basis.forward)
                guard forward > 0.06 else { return nil }
                return CGPoint(x: centerX + simd_dot(direction, basis.right) / forward * focal,
                               y: centerY - simd_dot(direction, basis.up) / forward * focal)
            },
            pointing: basis.pointing
        )
    }

    /// ARKit camera mode: project through the real camera's view/projection matrices
    /// (so overlays line up with the live image), with an azimuth calibration offset
    /// rotating everything about the vertical to cancel compass error.
    static func ar(camera: ARCamera, azimuthOffset: Angle, size: CGSize,
                   orientation: UIInterfaceOrientation = .portrait) -> SkyCamera {
        let view = camera.viewMatrix(for: orientation)
        let projection = camera.projectionMatrix(for: orientation, viewportSize: size, zNear: 0.01, zFar: 1000)
        let viewProjection = projection * view
        let cosOffset = cos(azimuthOffset.radians), sinOffset = sin(azimuthOffset.radians)
        let width = Double(size.width), height = Double(size.height)

        // (north, west, up) → ARKit gravityAndHeading world (east, up, south),
        // with the calibration rotation applied about the up axis.
        func toARWorld(_ d: SIMD3<Double>) -> SIMD4<Float> {
            let east = -d.y, north = d.x, up = d.z
            let rotatedEast = east * cosOffset + north * sinOffset
            let rotatedNorth = north * cosOffset - east * sinOffset
            return SIMD4(Float(rotatedEast), Float(up), Float(-rotatedNorth), 0)
        }

        // Camera aim reported back in the true (de-calibrated) frame.
        let forward = -SIMD3<Double>(Double(camera.transform.columns.2.x),
                                     Double(camera.transform.columns.2.y),
                                     Double(camera.transform.columns.2.z))   // (east, up, south)
        let reportedAzimuth = atan2(forward.x, -forward.z)
        let altitude = asin(min(1, max(-1, forward.y)))
        let truePointing = (azimuth: (Angle.radians(reportedAzimuth) - azimuthOffset).normalized,
                            altitude: Angle.radians(altitude))

        return SkyCamera(
            projectDirection: { direction in
                let clip = viewProjection * toARWorld(direction)
                guard clip.w > 0 else { return nil }
                let ndcX = Double(clip.x / clip.w), ndcY = Double(clip.y / clip.w)
                return CGPoint(x: (ndcX * 0.5 + 0.5) * width,
                               y: (0.5 - ndcY * 0.5) * height)
            },
            pointing: truePointing
        )
    }
}
