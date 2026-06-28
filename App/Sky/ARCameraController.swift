import SwiftUI
import ARKit
import CoreImage
import AVFoundation

/// Owns the ARKit session that supplies the camera pose (and the live camera image).
///
/// We deliberately do NOT use `ARView`/`ARSCNView` for the passthrough: both rendered
/// a black background here even with a healthy session delivering frames. Instead we
/// run a bare `ARSession` for the pose and `currentCameraImage()` hands the live frame
/// to `ContentView`, which draws it as a plain SwiftUI `Image` inside the same
/// `TimelineView` as the star overlay — the rendering path that actually composites.
///
/// Uses `.gravity` (NOT `.gravityAndHeading`) world alignment on purpose: gravity
/// fixes the vertical, but heading is tracked purely by visual-inertial odometry —
/// which is stable — instead of being continuously nudged by the noisy compass
/// (that nudging is what made calibration drift when sweeping the phone). The
/// manual "Align" step supplies absolute heading, and the calibration offset
/// absorbs ARKit's arbitrary starting heading.
@MainActor
@Observable
final class ARCameraController {
    private let session = ARSession()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private(set) var isRunning = false

    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    func start() {
        guard ARWorldTrackingConfiguration.isSupported else { return }
        // ARKit will only deliver camera frames once permission is granted. Don't rely
        // on its implicit prompt (which doesn't reliably fire here, e.g. on a fresh
        // sideload where authorization resets to `.notDetermined`): request explicitly
        // and run the session as soon as access is granted.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            runSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                Task { @MainActor in self?.runSession() }
            }
        case .denied, .restricted:
            break   // The UI surfaces an "enable in Settings" prompt for this case.
        @unknown default:
            break
        }
    }

    private func runSession() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = []
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
    }

    func stop() {
        session.pause()
        isRunning = false
    }

    /// Latest tracked frame (camera pose + intrinsics), read once per render frame.
    var currentFrame: ARFrame? { session.currentFrame }

    /// The live camera image as a `CGImage`, rotated for a portrait viewport.
    /// `capturedImage` is delivered in the sensor's landscape orientation, so we
    /// orient it `.right` to stand it up for a portrait-held phone.
    func currentCameraImage() -> CGImage? {
        guard let pixelBuffer = session.currentFrame?.capturedImage else { return nil }
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        return ciContext.createCGImage(image, from: image.extent)
    }
}
