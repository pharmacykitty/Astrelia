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

/// Imperative side-channel from the fly loop to the renderer for dive playback.
/// The dive must not depend on a SwiftUI render to start or advance: under the
/// 60 Hz flight churn SwiftUI's update graph can wedge (observed on simulator,
/// AttributeGraph cycle) and stop pushing cameras entirely — the display link
/// keeps running regardless, so the renderer reads this box directly each frame.
@MainActor
final class DiveChannel {
    var start: Date?
    var entryEye = SIMD3<Float>(0, 0, 0)
    var entryForward = SIMD3<Float>(0, 0, -1)
    var reduceMotion = false
}

/// Dive staging pushed into the lens pass (all 0 = the hole just sits there).
/// Swift sequences the beats; the shader stays dumb (docs/black-hole-dive.md).
struct DiveStage: Equatable {
    var beta: Float = 0        // infall speed v/c → aberration + Doppler headlight
    var bakeMix: Float = 0     // 0 = screen-space background, 1 = baked equirect sky
    var aperture: Float = 0    // outside universe collapsing to nothing
    var spaghetti: Float = 0   // tidal radial stretch
    var redshift: Float = 0    // global red/dim death of the light
    var flash: Float = 0       // final white-out
    var discBoost: Float = 0   // disc flare during the plunge
}

/// Per-frame camera state handed to the renderer. `viewProj` is built camera-relative
/// (eye at the origin); `eye` is the true world camera position the shader subtracts.
struct GalaxyCamera {
    var viewProj: simd_float4x4
    var eye: SIMD3<Float>
    var halfHeightFocal: Float    // (viewportHeight/2)·focal, points
    var viewSize: CGSize          // points

    // Gravitational lensing (Sgr A*). `holeRs ≤ 0` skips the lens pass entirely —
    // the scene renders straight to the drawable exactly as before.
    var holePos: SIMD3<Float> = .zero      // world (pc)
    var holeRs: Float = 0                  // Schwarzschild radius, stylised (pc)
    var diskInner: Float = 0               // ISCO (pc)
    var diskOuter: Float = 0               // disc outer edge (pc)
    var diskNormal: SIMD3<Float> = SIMD3(0, 0, 1)
    var right: SIMD3<Float> = SIMD3(1, 0, 0)   // camera basis for per-pixel rays
    var up: SIMD3<Float> = SIMD3(0, 1, 0)
    var forward: SIMD3<Float> = SIMD3(0, 0, -1)
    var tanHalfW: Float = 1
    var tanHalfH: Float = 1
    var dive = DiveStage()
    /// Drawable-resolution multiplier (≤ 1). Dropped while the camera is inside the
    /// geodesic-march zone: every pixel is then ray-marched, which the simulator's
    /// software Metal cannot survive at native scale (and even device GPUs
    /// appreciate the discount mid-dive, per docs/black-hole-dive.md).
    var renderScale: CGFloat = 1

    // Dive playback (the easter egg): while `diveStart` is set the RENDERER owns
    // the camera — pose and stage are pure functions of wall-clock time, computed
    // per display-link frame. SwiftUI only narrates (HUD text at a few Hz); a 60 Hz
    // @State camera loop starves SwiftUI rendering entirely on the simulator.
    var diveStart: Date?
    var diveEntryEye: SIMD3<Float> = .zero
    var diveEntryForward: SIMD3<Float> = SIMD3(0, 0, -1)
    var diveReduceMotion = false
    var fovY: Float = 0.9
    var aspect: Float = 0.5
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

/// Matches `LensUniforms` in GalaxyLensing.metal — float4x4 + 8 rows of 4 scalars
/// (192 bytes), no SIMD3 members so the layouts agree byte-for-byte.
private struct LensUniforms {
    var viewProj: simd_float4x4
    var rx: Float, ry: Float, rz: Float, tanHalfW: Float
    var ux: Float, uy: Float, uz: Float, tanHalfH: Float
    var fx: Float, fy: Float, fz: Float, time: Float
    var hx: Float, hy: Float, hz: Float, rs: Float
    var dnx: Float, dny: Float, dnz: Float, diskInner: Float
    var diskOuter: Float, beta: Float, bakeMix: Float, aperture: Float
    var spaghetti: Float, redshiftG: Float, flash: Float, discBoost: Float
    var viewW: Float, viewH: Float, pad0: Float, pad1: Float
}

/// Matches `BakeUniforms` in GalaxyLensing.metal (8 scalars, 32 bytes).
private struct BakeUniforms {
    var hx: Float, hy: Float, hz: Float, skipRadius: Float
    var texW: Float, texH: Float, pad0: Float, pad1: Float
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

    // Black-hole lens pass (GalaxyLensing.metal): the sprite scene renders into an
    // offscreen texture and the lens pass bends it around Sgr A* on the way to the
    // drawable. Only engaged while `camera.holeRs > 0`.
    private let lensPipeline: MTLRenderPipelineState?
    private let bakePipeline: MTLRenderPipelineState?
    private let blitPipeline: MTLRenderPipelineState?
    private var camera = GalaxyCamera(viewProj: matrix_identity_float4x4, eye: .zero,
                                      halfHeightFocal: 1, viewSize: .zero)
    private var sceneColor: MTLTexture?
    private var sceneDepth: MTLTexture?
    private var lensOut: MTLTexture?        // reduced-res lens result, upscaled by the blit
    private var skyBake: MTLTexture?        // equirect panorama from the hole (bent-ray fallback)
    private var bakedVersion = -1           // scene version the panorama was baked from
    private var blackSky: MTLTexture?       // 1×1 placeholder so the sampler always has a texture
    private let timeBase = CACurrentMediaTime()

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

        // Full-screen lens pass: blending off — it rewrites the drawable outright
        // (passthrough pixels copy the offscreen scene 1:1).
        lensPipeline = {
            guard let device, let library = device.makeDefaultLibrary(),
                  let vfn = library.makeFunction(name: "lens_vertex"),
                  let ffn = library.makeFunction(name: "lens_fragment") else { return nil }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vfn
            desc.fragmentFunction = ffn
            desc.depthAttachmentPixelFormat = .depth32Float
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            return try? device.makeRenderPipelineState(descriptor: desc)
        }()
        // Upscale blit: reduced-res lens result → native drawable.
        blitPipeline = {
            guard let device, let library = device.makeDefaultLibrary(),
                  let vfn = library.makeFunction(name: "lens_vertex"),
                  let ffn = library.makeFunction(name: "blit_fragment") else { return nil }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vfn
            desc.fragmentFunction = ffn
            desc.depthAttachmentPixelFormat = .depth32Float
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            return try? device.makeRenderPipelineState(descriptor: desc)
        }()
        // Equirect sky bake: additive sprites into the panorama, no depth.
        bakePipeline = {
            guard let device, let library = device.makeDefaultLibrary(),
                  let vfn = library.makeFunction(name: "bake_vertex"),
                  let ffn = library.makeFunction(name: "bake_fragment") else { return nil }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vfn
            desc.fragmentFunction = ffn
            let att = desc.colorAttachments[0]!
            att.pixelFormat = .bgra8Unorm
            att.isBlendingEnabled = true
            att.rgbBlendOperation = .add
            att.alphaBlendOperation = .add
            att.sourceRGBBlendFactor = .one;   att.destinationRGBBlendFactor = .one
            att.sourceAlphaBlendFactor = .one; att.destinationAlphaBlendFactor = .one
            return try? device.makeRenderPipelineState(descriptor: desc)
        }()
        blackSky = {
            guard let device else { return nil }
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                             width: 1, height: 1, mipmapped: false)
            d.usage = .shaderRead
            let tex = device.makeTexture(descriptor: d)
            var zero: UInt32 = 0
            tex?.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                         withBytes: &zero, bytesPerRow: 4)
            return tex
        }()

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
        self.camera = camera
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

    /// (Re)creates the offscreen colour+depth pair (and the lens output when the
    /// lens is rendering below drawable resolution) at the given pixel size.
    private func ensureOffscreen(_ size: CGSize, needsLensOut: Bool) -> Bool {
        let w = Int(size.width), h = Int(size.height)
        guard let device, w > 0, h > 0 else { return false }
        if sceneColor?.width != w || sceneColor?.height != h {
            let cd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                              width: w, height: h, mipmapped: false)
            cd.usage = [.renderTarget, .shaderRead]
            cd.storageMode = .private
            let dd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                                                              width: w, height: h, mipmapped: false)
            dd.usage = .renderTarget
            dd.storageMode = .private
            sceneColor = device.makeTexture(descriptor: cd)
            sceneDepth = device.makeTexture(descriptor: dd)
        }
        if needsLensOut, lensOut?.width != w || lensOut?.height != h {
            let ld = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                              width: w, height: h, mipmapped: false)
            ld.usage = [.renderTarget, .shaderRead]
            ld.storageMode = .shared   // CPU-readable for the debug frame dump
            lensOut = device.makeTexture(descriptor: ld)
        }
        return sceneColor != nil && sceneDepth != nil && (!needsLensOut || lensOut != nil)
    }

    // Debug (`-dumpDive`): periodically write the lens output to Documents so the
    // dive's real rendered frames can be inspected headlessly (the simulator's
    // SwiftUI chrome can wedge mid-dive, but these are the GPU's ground truth).
    private let dumpFrames = ProcessInfo.processInfo.arguments.contains("-dumpDive")
    private var lastDump: CFTimeInterval = 0

    private nonisolated static func writeDump(_ tex: MTLTexture, tag: String) {
        let w = tex.width, h = tex.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { buf in
            tex.getBytes(buf.baseAddress!, bytesPerRow: w * 4,
                         from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue |
                                                        CGBitmapInfo.byteOrder32Little.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false,
                               intent: .defaultIntent),
              let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let png = UIImage(cgImage: cg).pngData() else { return }
        try? png.write(to: dir.appendingPathComponent("dive_\(tag).png"))
    }

    /// While diving, the camera pose and dive stage are recomputed per frame from
    /// the wall clock — display-link smooth, no SwiftUI involvement. Also refreshes
    /// the sprite-pass uniforms so the scene itself tracks the dive camera.
    /// Reads the imperative `DiveChannel` first: the last SwiftUI camera push may
    /// predate the trigger, but it already carries the hole/fov parameters.
    var diveChannel: DiveChannel?

    private func applyDiveCamera() {
        guard camera.holeRs > 0, let start = diveChannel?.start ?? camera.diveStart else { return }
        let entryEye = diveChannel?.start != nil ? diveChannel!.entryEye : camera.diveEntryEye
        let entryForward = diveChannel?.start != nil ? diveChannel!.entryForward : camera.diveEntryForward
        let reduceMotion = diveChannel?.start != nil ? diveChannel!.reduceMotion : camera.diveReduceMotion
        let p = min(1, Date().timeIntervalSince(start) / DiveTimeline.duration)
        camera.dive = DiveTimeline.stage(at: p, reduceMotion: reduceMotion)

        let axis = simd_normalize(camera.holePos - entryEye)
        // Ease the view onto the infall axis over the opening beat.
        let a = Float(min(1, p / 0.12))
        let eased = a * a * (3 - 2 * a)
        var forward = simd_normalize(entryForward + (axis - entryForward) * eased)
        if simd_length_squared(forward) < 1e-6 { forward = axis }

        let rs = camera.holeRs
        let startRs = simd_distance(entryEye, camera.holePos) / max(rs, 1e-4)
        let eye = camera.holePos - axis * (DiveTimeline.holdDistanceRs(at: p, from: startRs) * rs)

        var side = simd_cross(forward, SIMD3<Float>(0, 1, 0))
        side = simd_length(side) < 1e-4 ? SIMD3(1, 0, 0) : simd_normalize(side)
        let up = simd_cross(side, forward)

        // Camera-relative look-at (eye at origin) + perspective, matching makeCamera.
        let f = forward
        let view = simd_float4x4(columns: (
            SIMD4(side.x, up.x, -f.x, 0),
            SIMD4(side.y, up.y, -f.y, 0),
            SIMD4(side.z, up.z, -f.z, 0),
            SIMD4(0, 0, 0, 1)
        ))
        let yScale = 1 / tan(camera.fovY * 0.5)
        let xScale = yScale / max(camera.aspect, 1e-4)
        let zScale: Float = 200000 / (0.05 - 200000)
        let projection = simd_float4x4(columns: (
            SIMD4(xScale, 0, 0, 0),
            SIMD4(0, yScale, 0, 0),
            SIMD4(0, 0, zScale, -1),
            SIMD4(0, 0, zScale * 0.05, 0)
        ))
        camera.viewProj = projection * view
        camera.eye = eye
        camera.forward = forward
        camera.right = side
        camera.up = up

        uniforms.viewProj = camera.viewProj
        uniforms.ex = eye.x; uniforms.ey = eye.y; uniforms.ez = eye.z
    }

    private func makeLensUniforms() -> LensUniforms {
        let c = camera
        let hp = c.holePos - c.eye        // camera-relative, like everything GPU-side
        return LensUniforms(viewProj: c.viewProj,
                            rx: c.right.x, ry: c.right.y, rz: c.right.z, tanHalfW: c.tanHalfW,
                            ux: c.up.x, uy: c.up.y, uz: c.up.z, tanHalfH: c.tanHalfH,
                            fx: c.forward.x, fy: c.forward.y, fz: c.forward.z,
                            time: Float(CACurrentMediaTime() - timeBase),
                            hx: hp.x, hy: hp.y, hz: hp.z, rs: c.holeRs,
                            dnx: c.diskNormal.x, dny: c.diskNormal.y, dnz: c.diskNormal.z,
                            diskInner: c.diskInner,
                            diskOuter: c.diskOuter, beta: c.dive.beta,
                            bakeMix: skyBake == nil ? 0 : c.dive.bakeMix, aperture: c.dive.aperture,
                            spaghetti: c.dive.spaghetti, redshiftG: c.dive.redshift,
                            flash: c.dive.flash, discBoost: c.dive.discBoost,
                            viewW: Float(c.viewSize.width), viewH: Float(c.viewSize.height),
                            pad0: 0, pad1: 0)
    }

    /// Renders the additive scene into the equirect panorama, as seen from the hole.
    /// Re-baked only when the scene itself changes (art toggles, catalogue load).
    private func bakeSkyIfNeeded(_ cb: MTLCommandBuffer) {
        guard camera.holeRs > 0, bakedVersion != loadedVersion,
              let device, let bakePipeline else { return }
        if skyBake == nil {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                             width: 2048, height: 1024, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            skyBake = device.makeTexture(descriptor: d)
        }
        guard let skyBake else { return }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = skyBake
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        var bu = BakeUniforms(hx: camera.holePos.x, hy: camera.holePos.y, hz: camera.holePos.z,
                              skipRadius: camera.holeRs * 2.5,
                              texW: 2048, texH: 1024, pad0: 0, pad1: 0)
        enc.setRenderPipelineState(bakePipeline)
        for (buffer, count) in [(additiveBuffer, additiveCount), (landmarkBuffer, landmarkCount)] {
            guard count > 0, let buffer else { continue }
            enc.setVertexBuffer(buffer, offset: 0, index: 0)
            enc.setVertexBytes(&bu, length: MemoryLayout<BakeUniforms>.stride, index: 1)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
        }
        enc.endEncoding()
        bakedVersion = loadedVersion
    }

    private func render(in view: MTKView) {
        guard let queue, let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cb = queue.makeCommandBuffer() else { return }

        applyDiveCamera()
        bakeSkyIfNeeded(cb)
        // Near the hole the whole frame is ray-marched, so scene + lens render into
        // internal textures at a reduced pixel size and a final blit upscales to the
        // native drawable. All internal: the MTKView/layer never change scale (doing
        // that mid-flight corrupts SwiftUI's update graph and wedges the window).
        let scale = CGFloat(max(0.05, min(1, camera.renderScale)))
        let reduced = scale < 0.999
        let lensSize = CGSize(width: (view.drawableSize.width * scale).rounded(.down),
                              height: (view.drawableSize.height * scale).rounded(.down))
        if camera.holeRs > 0, let lensPipeline, let blitPipeline,
           ensureOffscreen(lensSize, needsLensOut: reduced),
           let sceneColor, let sceneDepth {
            // 1) Sprite scene → offscreen (identical passes, reduced target).
            let off = MTLRenderPassDescriptor()
            off.colorAttachments[0].texture = sceneColor
            off.colorAttachments[0].loadAction = .clear
            off.colorAttachments[0].storeAction = .store
            off.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            off.depthAttachment.texture = sceneDepth
            off.depthAttachment.loadAction = .clear
            off.depthAttachment.storeAction = .dontCare
            off.depthAttachment.clearDepth = 1.0
            encodeSprites(cb, into: off)

            // 2) Lens pass: bends the scene around the hole, draws the shadow /
            //    photon ring / disc in place — into the drawable directly at full
            //    scale, or into lensOut when reduced.
            let lensTarget: MTLRenderPassDescriptor
            if reduced, let lensOut {
                lensTarget = MTLRenderPassDescriptor()
                lensTarget.colorAttachments[0].texture = lensOut
                lensTarget.colorAttachments[0].loadAction = .dontCare
                lensTarget.colorAttachments[0].storeAction = .store
            } else {
                lensTarget = rpd
            }
            if let enc = cb.makeRenderCommandEncoder(descriptor: lensTarget) {
                enc.setRenderPipelineState(lensPipeline)
                if let noDepthState { enc.setDepthStencilState(noDepthState) }
                var lu = makeLensUniforms()
                enc.setFragmentBytes(&lu, length: MemoryLayout<LensUniforms>.stride, index: 0)
                enc.setFragmentTexture(sceneColor, index: 0)
                enc.setFragmentTexture(skyBake ?? blackSky, index: 1)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                enc.endEncoding()
            }

            // 3) Upscale blit → drawable (reduced path only).
            if reduced, let lensOut, let enc = cb.makeRenderCommandEncoder(descriptor: rpd) {
                enc.setRenderPipelineState(blitPipeline)
                if let noDepthState { enc.setDepthStencilState(noDepthState) }
                enc.setFragmentTexture(lensOut, index: 0)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                enc.endEncoding()
            }

            if dumpFrames, reduced, let start = diveChannel?.start ?? camera.diveStart, let lensOut,
               CACurrentMediaTime() - lastDump > 2.5 {
                lastDump = CACurrentMediaTime()
                let p = min(1, Date().timeIntervalSince(start) / DiveTimeline.duration)
                let tag = String(format: "p%03d", Int(p * 100))
                cb.addCompletedHandler { _ in Self.writeDump(lensOut, tag: tag) }
            }
        } else {
            encodeSprites(cb, into: rpd)
        }

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
    var diveChannel: DiveChannel? = nil

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
        context.coordinator.diveChannel = diveChannel
        context.coordinator.update(scene: scene, version: sceneVersion, camera: camera)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.diveChannel = diveChannel
        context.coordinator.update(scene: scene, version: sceneVersion, camera: camera)
    }
}
