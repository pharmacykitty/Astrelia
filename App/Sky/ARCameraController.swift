import SwiftUI
import ARKit
import CoreImage
import AVFoundation

/// Owns the ARKit session that supplies the camera pose (and the live camera image).
///
/// We deliberately do NOT use `ARView`/`ARSCNView` for the passthrough: both rendered
/// a black background here even with a healthy session delivering frames. Instead we
/// run a bare `ARSession` for the pose and draw the camera image ourselves as a plain
/// SwiftUI `Image` (see `ARCameraView`) — the same rendering path that already draws
/// the star overlay reliably.
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

/// Draws the live camera image as the SwiftUI background for AR mode, aspect-filled
/// to the screen. Rebuilt each frame so the feed stays live.
struct ARCameraView: View {
    let controller: ARCameraController

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { _ in
                let frame = controller.currentFrame
                let image = controller.currentCameraImage()
                ZStack {
                    Color.black
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    }
                    // DIAGNOSTIC HUD — remove once the camera shows.
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AR running: \(controller.isRunning ? "yes" : "no")")
                        Text("frame: \(frame != nil ? "yes" : "no")")
                        if let buffer = frame?.capturedImage {
                            Text("buf: \(CVPixelBufferGetWidth(buffer))×\(CVPixelBufferGetHeight(buffer))")
                        } else {
                            Text("buf: none")
                        }
                        Text("cgimage: \(image != nil ? "yes" : "no")")
                        Text("tracking: \(trackingDescription(frame?.camera.trackingState))")
                    }
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)
                    .padding(8)
                    .background(.black.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 140)
                    .padding(.leading, 16)
                }
            }
        }
    }

    private func trackingDescription(_ state: ARCamera.TrackingState?) -> String {
        switch state {
        case .normal: return "normal"
        case .limited(let reason): return "limited(\(reason))"
        case .notAvailable: return "notAvailable"
        case nil: return "nil"
        }
    }
}
