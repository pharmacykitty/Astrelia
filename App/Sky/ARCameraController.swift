import SwiftUI
import ARKit
import RealityKit
import AVFoundation

/// Owns the ARKit session and the `ARView` that shows the live camera feed.
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
    let arView = ARView(frame: .zero)
    private(set) var isRunning = false

    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    func start() {
        guard ARWorldTrackingConfiguration.isSupported else { return }
        // We drive the session ourselves (with `.gravity` alignment); without this,
        // RealityKit runs its own config early — before camera permission resolves —
        // and races our run, which can leave the passthrough feed blank.
        arView.automaticallyConfigureSession = false

        // ARKit will only show the camera once permission is granted. Don't rely on
        // its implicit prompt (which doesn't reliably fire here, e.g. on a fresh
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
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
    }

    func stop() {
        arView.session.pause()
        isRunning = false
    }

    /// Latest tracked frame (camera pose + intrinsics), read once per render frame.
    var currentFrame: ARFrame? { arView.session.currentFrame }
}

/// Hosts the camera `ARView` as the SwiftUI background for AR mode.
struct ARCameraView: UIViewRepresentable {
    let controller: ARCameraController
    func makeUIView(context: Context) -> ARView { controller.arView }
    func updateUIView(_ uiView: ARView, context: Context) {}
}
