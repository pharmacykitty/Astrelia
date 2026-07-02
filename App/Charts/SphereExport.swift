import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import AVFoundation
import CoreMedia
import CoreVideo

/// Which way to export the rotating sphere.
enum SphereExportFormat: String, CaseIterable, Identifiable {
    case gif, mp4
    var id: String { rawValue }
    var title: String {
        switch self {
        case .gif: "Animated GIF"
        case .mp4: "Video (MP4)"
        }
    }
    var systemImage: String {
        switch self {
        case .gif: "rectangle.stack"
        case .mp4: "film"
        }
    }

    /// How to render the rotation for this format — paced to ~10 s for one full
    /// turn. The GIF gets fewer, smaller frames (GIF compresses a star field
    /// poorly); the video stays full-resolution and smooth.
    var renderPlan: SphereRenderPlan {
        switch self {
        case .gif: SphereRenderPlan(count: 140, dimension: 360, scale: 1, fps: 14)
        case .mp4: SphereRenderPlan(count: 200, dimension: 540, scale: 2, fps: 20)
        }
    }
}

/// Frame budget + cadence for rendering a sphere rotation.
struct SphereRenderPlan {
    let count: Int
    let dimension: CGFloat
    let scale: CGFloat
    let fps: Double
}

/// The outcome of an export: a file to share, or a message.
enum SphereExportResult {
    case shareFile(URL)
    case failure(String)
}

/// Turns a sequence of rendered rotation frames into a shareable GIF/MP4. Pure
/// file/codec work — the frames are produced by `CelestialSphereView` via
/// `ImageRenderer`.
enum SphereExport {
    static func make(_ format: SphereExportFormat, frames: [CGImage],
                     fps: Double, title: String) async -> SphereExportResult {
        guard !frames.isEmpty else { return .failure("Nothing to render.") }
        switch format {
        case .gif:
            if let url = encodeGIF(frames, fps: fps, title: title) { return .shareFile(url) }
            return .failure("Couldn't create the GIF.")
        case .mp4:
            let url = tempURL(title, "mp4")
            let ok = await encodeVideo(frames, fps: fps, url: url)
            return ok ? .shareFile(url) : .failure("Couldn't create the video.")
        }
    }

    // MARK: GIF

    private static func encodeGIF(_ frames: [CGImage], fps: Double, title: String) -> URL? {
        let url = tempURL(title, "gif")
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { return nil }
        CGImageDestinationSetProperties(dest, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)
        let frameProps = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: 1.0 / fps]
        ] as CFDictionary
        for frame in frames { CGImageDestinationAddImage(dest, frame, frameProps) }
        return CGImageDestinationFinalize(dest) ? url : nil
    }

    // MARK: Video (MP4)

    private static func encodeVideo(_ frames: [CGImage], fps: Double, url: URL) async -> Bool {
        let width = frames[0].width, height = frames[0].height
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return false }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ])
        guard writer.canAdd(videoInput) else { return false }
        writer.add(videoInput)

        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        for (i, frame) in frames.enumerated() {
            while !videoInput.isReadyForMoreMediaData { await Task.yield() }
            guard let buffer = pixelBuffer(from: frame, width: width, height: height,
                                           pool: adaptor.pixelBufferPool) else { continue }
            adaptor.append(buffer, withPresentationTime: CMTimeMultiply(frameDuration, multiplier: Int32(i)))
        }
        videoInput.markAsFinished()

        await writer.finishWriting()
        return writer.status == .completed
    }

    private static func pixelBuffer(from image: CGImage, width: Int, height: Int,
                                    pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb)
        } else {
            CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB,
                                [kCVPixelBufferCGImageCompatibilityKey: true,
                                 kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &pb)
        }
        guard let buffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    // MARK: Files

    private static func tempURL(_ title: String, _ ext: String) -> URL {
        let safe = title.isEmpty ? "sphere" : title.replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined()
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("astrolabe-\(safe.isEmpty ? "sphere" : safe)").appendingPathExtension(ext)
    }
}

/// A wrapped URL so the share sheet can be driven by `.sheet(item:)`.
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// A thin `UIActivityViewController` wrapper for sharing a file URL.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
