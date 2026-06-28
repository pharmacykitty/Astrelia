import SwiftUI
import ARKit
import SceneKit
import AVFoundation

/// Owns the ARKit session and the `ARSCNView` that shows the live camera feed.
///
/// We use `ARSCNView` purely as a camera-passthrough backdrop — all of our sky
/// overlay is drawn in SwiftUI on top, so we never add SceneKit content. (RealityKit's
/// `ARView` was rendering a black background here even with a running session; `ARSCNView`
/// reliably displays the captured camera image with an empty scene.)
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
    let sceneView = ARSCNView(frame: .zero)
    private(set) var isRunning = false

    private var session: ARSession { sceneView.session }

    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    func start() {
        guard ARWorldTrackingConfiguration.isSupported else { return }
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
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
    }

    func stop() {
        session.pause()
        isRunning = false
    }

    /// Latest tracked frame (camera pose + intrinsics), read once per render frame.
    var currentFrame: ARFrame? { session.currentFrame }
}

/// Hosts the camera `ARSCNView` as the SwiftUI background for AR mode.
struct ARCameraView: UIViewRepresentable {
    let controller: ARCameraController
    func makeUIView(context: Context) -> ARSCNView {
        let view = controller.sceneView
        view.backgroundColor = .red   // DIAGNOSTIC: shows through only if the camera feed isn't drawing.
        return view
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}
