import SwiftUI
import ARKit
import RealityKit

/// Owns the ARKit session and the `ARView` that shows the live camera feed.
/// Uses `.gravityAndHeading` world alignment so ARKit's world axes line up with
/// compass + gravity (x = east, y = up, z = south), matching our projection math.
@MainActor
@Observable
final class ARCameraController {
    let arView = ARView(frame: .zero)
    private(set) var isRunning = false

    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    func start() {
        guard ARWorldTrackingConfiguration.isSupported else { return }
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
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
