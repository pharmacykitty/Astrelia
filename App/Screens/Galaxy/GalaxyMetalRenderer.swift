import SwiftUI
import MetalKit
import simd

// GPU renderer for the Galaxy Map. Everything on screen is expressed as instanced,
// billboarded soft sprites (see GalaxyShaders.metal): additive ones for light
// (stars, the Milky Way, nebula gas, glows) and normal-blend ones for dark dust /
// event horizons. Instances are built once in world space; the camera moves via
// per-frame uniforms, so the GPU does all the projection. This replaces the SwiftUI
// `Canvas` path for scale (100k+ points) and float precision (camera-relative coords
// + logarithmic depth).

/// One sprite instance. A flat run of 12 `Float`s so the Swift and Metal layouts
/// match byte-for-byte (no `float3` alignment surprises).
struct GalaxySprite {
    var px: Float, py: Float, pz: Float   // world position (parsecs)
    var radius: Float                     // world radius (mode 0) or screen coefficient (mode 1)
    var r: Float, g: Float, b: Float, a: Float
    var minPixel: Float, maxPixel: Float  // size clamp (points)
    var softness: Float                   // 0 = hard disc, 1 = soft glow
    var mode: Float                       // 0 = world-sized, 1 = screen-sized

    init(position: SIMD3<Float>, radius: Float, color: SIMD4<Float>,
         minPixel: Float, maxPixel: Float, softness: Float, mode: Float) {
        px = position.x; py = position.y; pz = position.z
        self.radius = radius
        r = color.x; g = color.y; b = color.z; a = color.w
        self.minPixel = minPixel; self.maxPixel = maxPixel
        self.softness = softness; self.mode = mode
    }
}

/// The two instance lists, by blend mode. Built on the main thread from the catalogue
/// + art, then uploaded to GPU buffers when `version` changes.
struct GalaxyScene {
    var additive: [GalaxySprite] = []      // occludee light (stars, Milky Way) — tests depth
    var landmarkLight: [GalaxySprite] = [] // landmark/nebula light — no depth interaction
    var occluder: [GalaxySprite] = []      // invisible depth-only caps (dense, opaque cores)
    var overlay: [GalaxySprite] = []       // dark dust / horizons (srcAlpha, 1−srcAlpha)
}

/// Per-frame camera state handed to the renderer. `viewProj` is built camera-relative
/// (eye at the origin); `eye` is the true world camera position the shader subtracts.
struct GalaxyCamera {
    var viewProj: simd_float4x4
    var eye: SIMD3<Float>
    var halfHeightFocal: Float    // (viewportHeight/2)·focal, points
    var viewSize: CGSize          // points
}

/// Matches `Uniforms` in the shader (float4x4 then 8 floats → 96 bytes).
private struct GalaxyUniforms {
    var viewProj: simd_float4x4
    var ex: Float, ey: Float, ez: Float
    var halfHeightFocal: Float
    var viewW: Float, viewH: Float
    var logDepthC: Float
    var pad0: Float
}

@MainActor
final class GalaxyMetalRenderer: NSObject {
    let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private let additivePipeline: MTLRenderPipelineState?
    private let occluderPipeline: MTLRenderPipelineState?  // depth-only caps (dense nebula cores)
    private let overlayPipeline: MTLRenderPipelineState?

    // Depth states for nebula occlusion: caps write depth; occludee light tests it
    // (no write, so the additive star glow never occludes itself); everything else ignores depth.
    private let occluderDepthState: MTLDepthStencilState?   // write, .less
    private let occludeeDepthState: MTLDepthStencilState?   // test (.lessEqual), no write
    private let noDepthState: MTLDepthStencilState?         // .always, no write

    private var additiveBuffer: MTLBuffer?
    private var landmarkBuffer: MTLBuffer?
    private var occluderBuffer: MTLBuffer?
    private var overlayBuffer: MTLBuffer?
    private var additiveCount = 0
    private var landmarkCount = 0
    private var occluderCount = 0
    private var overlayCount = 0
    private var loadedVersion = -1
    private var uniforms = GalaxyUniforms(viewProj: matrix_identity_float4x4, ex: 0, ey: 0, ez: 0,
                                          halfHeightFocal: 1, viewW: 1, viewH: 1, logDepthC: 0.0008, pad0: 0)

    override init() {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        queue = device?.makeCommandQueue()

        func pipeline(_ fragment: String, additive: Bool) -> MTLRenderPipelineState? {
            guard let device, let library = device.makeDefaultLibrary(),
                  let vfn = library.makeFunction(name: "sprite_vertex"),
                  let ffn = library.makeFunction(name: fragment) else { return nil }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vfn
            desc.fragmentFunction = ffn
            desc.depthAttachmentPixelFormat = .depth32Float
            let att = desc.colorAttachments[0]!
            att.pixelFormat = .bgra8Unorm
            att.isBlendingEnabled = true
            att.rgbBlendOperation = .add
            att.alphaBlendOperation = .add
            if additive {
                att.sourceRGBBlendFactor = .one;        att.destinationRGBBlendFactor = .one
                att.sourceAlphaBlendFactor = .one;      att.destinationAlphaBlendFactor = .one
            } else {
                att.sourceRGBBlendFactor = .sourceAlpha; att.destinationRGBBlendFactor = .oneMinusSourceAlpha
                att.sourceAlphaBlendFactor = .sourceAlpha; att.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try? device.makeRenderPipelineState(descriptor: desc)
        }
        additivePipeline = pipeline("sprite_additive", additive: true)
        occluderPipeline = pipeline("sprite_occluder", additive: true)
        overlayPipeline = pipeline("sprite_overlay", additive: false)

        func depthState(_ compare: MTLCompareFunction, write: Bool) -> MTLDepthStencilState? {
            let d = MTLDepthStencilDescriptor()
            d.depthCompareFunction = compare
            d.isDepthWriteEnabled = write
            return device?.makeDepthStencilState(descriptor: d)
        }
        occluderDepthState = depthState(.less, write: true)
        occludeeDepthState = depthState(.lessEqual, write: false)
        noDepthState = depthState(.always, write: false)
        super.init()
    }

    /// Push the latest camera every frame; rebuild instance buffers when the scene
    /// (catalogue + art) actually changes.
    func update(scene: GalaxyScene, version: Int, camera: GalaxyCamera) {
        uniforms = GalaxyUniforms(viewProj: camera.viewProj,
                                  ex: camera.eye.x, ey: camera.eye.y, ez: camera.eye.z,
                                  halfHeightFocal: camera.halfHeightFocal,
                                  viewW: Float(camera.viewSize.width), viewH: Float(camera.viewSize.height),
                                  logDepthC: 0.0008, pad0: 0)
        guard version != loadedVersion else { return }
        loadedVersion = version
        let stride = MemoryLayout<GalaxySprite>.stride
        additiveCount = scene.additive.count
        landmarkCount = scene.landmarkLight.count
        occluderCount = scene.occluder.count
        overlayCount = scene.overlay.count
        additiveBuffer = scene.additive.isEmpty ? nil
            : device?.makeBuffer(bytes: scene.additive, length: scene.additive.count * stride, options: .storageModeShared)
        landmarkBuffer = scene.landmarkLight.isEmpty ? nil
            : device?.makeBuffer(bytes: scene.landmarkLight, length: scene.landmarkLight.count * stride, options: .storageModeShared)
        occluderBuffer = scene.occluder.isEmpty ? nil
            : device?.makeBuffer(bytes: scene.occluder, length: scene.occluder.count * stride, options: .storageModeShared)
        overlayBuffer = scene.overlay.isEmpty ? nil
            : device?.makeBuffer(bytes: scene.overlay, length: scene.overlay.count * stride, options: .storageModeShared)
    }

    /// Draws the sprite layers (additive + dark overlay) into `descriptor`'s target.
    private func encodeSprites(_ cb: MTLCommandBuffer, into descriptor: MTLRenderPassDescriptor) {
        guard let additivePipeline, let overlayPipeline,
              let enc = cb.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        var u = uniforms
        let ulen = MemoryLayout<GalaxyUniforms>.stride

        func draw(_ pipeline: MTLRenderPipelineState?, _ buffer: MTLBuffer?, _ count: Int,
                  _ depth: MTLDepthStencilState?) {
            guard count > 0, let pipeline, let buffer else { return }
            enc.setRenderPipelineState(pipeline)
            if let depth { enc.setDepthStencilState(depth) }
            enc.setVertexBuffer(buffer, offset: 0, index: 0)
            enc.setVertexBytes(&u, length: ulen, index: 1)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
        }

        // 1) Invisible caps write the dense landmark cores into the depth buffer.
        draw(occluderPipeline, occluderBuffer, occluderCount, occluderDepthState)
        // 2) Occludee light (stars, Milky Way) tests depth → culled behind a cap, but
        //    never writes depth, so the additive star glow never occludes itself.
        draw(additivePipeline, additiveBuffer, additiveCount, occludeeDepthState)
        // 3) Landmark/nebula light renders in full, ignoring depth (no self-occlusion).
        draw(additivePipeline, landmarkBuffer, landmarkCount, noDepthState)
        // 4) Dark dust / event horizons, normal-blend, depth ignored.
        draw(overlayPipeline, overlayBuffer, overlayCount, noDepthState)
        enc.endEncoding()
    }

    private func render(in view: MTKView) {
        guard let queue, let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cb = queue.makeCommandBuffer() else { return }

        encodeSprites(cb, into: rpd)

        cb.present(drawable)
        cb.commit()
    }
}

extension GalaxyMetalRenderer: MTKViewDelegate {
    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    // MTKView drives this on the main thread via its display link.
    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { self.render(in: view) }
    }
}

/// SwiftUI host for the Metal renderer. The scene rebuilds when `sceneVersion`
/// changes; the camera updates every layout pass (gestures / free-fly animation).
struct GalaxyMetalView: UIViewRepresentable {
    var scene: GalaxyScene
    var sceneVersion: Int
    var camera: GalaxyCamera

    func makeCoordinator() -> GalaxyMetalRenderer { GalaxyMetalRenderer() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.colorPixelFormat = .bgra8Unorm
        // Depth buffer for nebula occlusion: caps write depth, background stars test it.
        view.depthStencilPixelFormat = .depth32Float
        view.clearDepth = 1.0
        view.framebufferOnly = true
        view.isOpaque = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        context.coordinator.update(scene: scene, version: sceneVersion, camera: camera)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.update(scene: scene, version: sceneVersion, camera: camera)
    }
}
