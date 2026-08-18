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
    // Anisotropy (nebula wisps): world-space stretch direction + elongation.
    // dir = 0 / aspect = 1 renders the classic round billboard. Kept as flat
    // scalars so the Swift and Metal layouts stay byte-identical (16 floats).
    var dx: Float, dy: Float, dz: Float
    var aspect: Float

    init(position: SIMD3<Float>, radius: Float, color: SIMD4<Float>,
         minPixel: Float, maxPixel: Float, softness: Float, mode: Float,
         direction: SIMD3<Float> = .zero, aspect: Float = 1) {
        px = position.x; py = position.y; pz = position.z
        self.radius = radius
        r = color.x; g = color.y; b = color.z; a = color.w
        self.minPixel = minPixel; self.maxPixel = maxPixel
        self.softness = softness; self.mode = mode
        dx = direction.x; dy = direction.y; dz = direction.z
        self.aspect = aspect
    }
}

/// The two instance lists, by blend mode. Built off the main actor from the
/// catalogue + art (`GalaxyMapView.buildScene`), then uploaded to GPU buffers when
/// `version` changes.
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

/// Matches `LensUniforms` in GalaxyLensing.metal — float4x4 + 7 rows of 4 scalars
/// (176 bytes), no SIMD3 members so the layouts agree byte-for-byte.
private struct LensUniforms {
    var viewProj: simd_float4x4
    var rx: Float, ry: Float, rz: Float, tanHalfW: Float
    var ux: Float, uy: Float, uz: Float, tanHalfH: Float
    var fx: Float, fy: Float, fz: Float, time: Float
    var hx: Float, hy: Float, hz: Float, rs: Float
    var dnx: Float, dny: Float, dnz: Float, diskInner: Float
    var diskOuter: Float, viewW: Float, viewH: Float, strength: Float
    var holeDepth: Float, pad1: Float, pad2: Float, pad3: Float
}

/// Matches `BakeUniforms` in GalaxyLensing.metal (8 scalars, 32 bytes).
private struct BakeUniforms {
    var ox: Float, oy: Float, oz: Float, skipRadius: Float   // bake origin = camera
    var hx: Float, hy: Float, hz: Float, holeSkip: Float     // hole pos + beacon cull
    var texW: Float, texH: Float, coreSkip: Float, pad1: Float
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
    private var lensScratchDepth: MTLTexture?
    private var lensOut: MTLTexture?        // reduced-res lens result, upscaled by the blit
    private var skyBake: MTLTexture?        // equirect panorama from the hole (bent-ray fallback)
    private var bakedVersion = -1           // scene version the panorama was baked from
    private var blackSky: MTLTexture?       // 1×1 placeholder so the sampler always has a texture
    // The disc's animation clock (drives the accretion swirl).
    private var discTime: Double = 0
    private var lastFrameTime = CACurrentMediaTime()
    // Idle-resolve: when the camera rests, the lens re-renders at higher resolution
    // (motion hides the budget scale's softness; a parked view shouldn't be crunchy).
    private var lastPose: (eye: SIMD3<Float>, fwd: SIMD3<Float>)?
    private var lastMoveTime = CACurrentMediaTime()

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
            // Mipmapped: the lens pass samples a blurred level for the un-lensed
            // foreground veil (the bulge fog in FRONT of the hole must not be
            // lensed away — without the veil the bent region punches a dark
            // "bubble" in the fog).
            let cd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                              width: w, height: h, mipmapped: true)
            cd.usage = [.renderTarget, .shaderRead]
            cd.storageMode = .private
            let dd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                                                              width: w, height: h, mipmapped: false)
            // shaderRead: the lens pass samples the scene depth for the
            // foreground guard (content nearer than the hole must not warp).
            dd.usage = [.renderTarget, .shaderRead]
            dd.storageMode = .private
            sceneColor = device.makeTexture(descriptor: cd)
            sceneDepth = device.makeTexture(descriptor: dd)
            // Bystander depth for the reduced lens pass (its PSO declares one);
            // it can't be sceneDepth itself once the shader samples that.
            lensScratchDepth = device.makeTexture(descriptor: dd)
        }
        if needsLensOut, lensOut?.width != w || lensOut?.height != h {
            let ld = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                              width: w, height: h, mipmapped: false)
            ld.usage = [.renderTarget, .shaderRead]
            ld.storageMode = .private
            lensOut = device.makeTexture(descriptor: ld)
        }
        return sceneColor != nil && sceneDepth != nil && (!needsLensOut || lensOut != nil)
    }

    // Debug (`-fpsLog`): print frame rate + lens scale every ~2 s.
    private let fpsLog = ProcessInfo.processInfo.arguments.contains("-fpsLog")
    private var frameCount = 0
    private var lastFPSLog = CACurrentMediaTime()

    private func makeLensUniforms() -> LensUniforms {
        let c = camera
        let hp = c.holePos - c.eye        // camera-relative, like everything GPU-side
        return LensUniforms(viewProj: c.viewProj,
                            rx: c.right.x, ry: c.right.y, rz: c.right.z, tanHalfW: c.tanHalfW,
                            ux: c.up.x, uy: c.up.y, uz: c.up.z, tanHalfH: c.tanHalfH,
                            fx: c.forward.x, fy: c.forward.y, fz: c.forward.z,
                            time: Float(discTime),
                            hx: hp.x, hy: hp.y, hz: hp.z, rs: c.holeRs,
                            dnx: c.diskNormal.x, dny: c.diskNormal.y, dnz: c.diskNormal.z,
                            diskInner: c.diskInner,
                            diskOuter: c.diskOuter,
                            viewW: Float(c.viewSize.width), viewH: Float(c.viewSize.height),
                            strength: lensStrength(hp: hp, rs: c.holeRs),
                            holeDepth: holeLogDepth(hp: hp, forward: c.forward),
                            pad1: 0, pad2: 0, pad3: 0)
    }

    /// Warp strength: eases the deflection out as the hole's influence disc
    /// shrinks below ~a degree on screen — from across the galaxy the ring is
    /// physically near sub-pixel, and full-strength warp visibly bent content
    /// sitting thousands of ly in front of the hole (device review 2026-08-10).
    private func lensStrength(hp: SIMD3<Float>, rs: Float) -> Float {
        let ang = atan2(rs * 20, max(simd_length(hp), 1e-3))
        let t = max(0, min(1, (ang - 0.02) / 0.04))
        return t * t * (3 - 2 * t)
    }

    /// The hole's depth in the sprite pass's log-depth encoding (sprite_vertex:
    /// log2(C·w + 1) / log2(C·200000 + 1), C = 0.0008, w = forward distance) —
    /// the foreground guard compares scene depth against this. < 0 ⇒ no guard.
    private func holeLogDepth(hp: SIMD3<Float>, forward: SIMD3<Float>) -> Float {
        let w = simd_dot(hp, forward)
        guard w > 0 else { return -1 }
        return log2(0.0008 * w + 1) / log2(0.0008 * 200000 + 1)
    }

    /// Renders the additive scene into the equirect panorama, as seen FROM THE
    /// CAMERA. It used to bake from the hole's position — the parallax mismatch
    /// between panorama and scene content made the strongly-bent region read as
    /// a different object stitched over the sky, no matter how the handoff was
    /// feathered. Camera-centred, the bent rays sample the same sky the screen
    /// shows and the lens region becomes THE background, bent. Re-baked when
    /// the scene version changes or the camera moves ≥5% of its hole distance
    /// (rate-limited).
    private var bakedEye = SIMD3<Float>(.nan, 0, 0)
    private var lastBakeTime: CFTimeInterval = 0

    private func bakeSkyIfNeeded(_ cb: MTLCommandBuffer) {
        guard camera.holeRs > 0, let device, let bakePipeline else { return }
        let holeDist = max(simd_distance(camera.eye, camera.holePos), camera.holeRs)
        // 12% + 0.5 s: at 5%/0.2 s an orbiting camera re-baked the whole sprite
        // scene (plus mips) up to 5×/s and frame rate tanked. The panorama only
        // drifts with POSITION (rotation is free in an equirect), and a 12%
        // parallax error at the lens region's edge is invisible.
        let moved = bakedEye.x.isNaN || simd_distance(bakedEye, camera.eye) > 0.12 * holeDist
        let now = CACurrentMediaTime()
        guard bakedVersion != loadedVersion || (moved && now - lastBakeTime > 0.5) else { return }
        if skyBake == nil {
            // Mipmapped: the lens pass samples this mip-filtered — without mips
            // the panorama's star sprites alias into confetti wherever the lens
            // magnifies or minifies the sky.
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                             width: 2048, height: 1024, mipmapped: true)
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
        // Origin = the camera. Cull only sprites hugging the camera itself (they
        // have no stable direction) and the hole's own beacon (the lens draws
        // the hole; its sprite glow must not also appear in the lensed sky).
        var bu = BakeUniforms(ox: camera.eye.x, oy: camera.eye.y, oz: camera.eye.z,
                              skipRadius: 0.4 * holeDist * 0.05,
                              hx: camera.holePos.x, hy: camera.holePos.y, hz: camera.holePos.z,
                              holeSkip: camera.holeRs * 2.5,
                              texW: 2048, texH: 1024, coreSkip: 400, pad1: 0)
        enc.setRenderPipelineState(bakePipeline)
        for (buffer, count) in [(additiveBuffer, additiveCount), (landmarkBuffer, landmarkCount)] {
            guard count > 0, let buffer else { continue }
            enc.setVertexBuffer(buffer, offset: 0, index: 0)
            enc.setVertexBytes(&bu, length: MemoryLayout<BakeUniforms>.stride, index: 1)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
        }
        enc.endEncoding()
        if let blit = cb.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: skyBake)
            blit.endEncoding()
        }
        bakedVersion = loadedVersion
        bakedEye = camera.eye
        lastBakeTime = now
    }

    /// Internal lens resolution from a march-cost budget. The expensive pixels are
    /// the ones whose rays integrate geodesics — roughly the hole's projected
    /// influence disc (the whole frame once the camera is inside it). Scaling the
    /// internal resolution so that count stays bounded keeps frame time flat all the
    /// way in; without this, the approach band just outside the influence radius
    /// marches nearly the full native frame and parks the main thread in
    /// `currentDrawable` — the "freeze as you get close". Floored to 0.1 steps so
    /// the offscreen textures only reallocate at discrete approach distances.
    private func lensScale(drawableSize: CGSize, idle: Bool) -> CGFloat {
        let area = drawableSize.width * drawableSize.height
        guard area > 1, camera.holeRs > 0 else { return 1 }
        #if targetEnvironment(simulator)
        let budget: CGFloat = 380_000     // the sim's Metal is far slower than any device GPU
        #else
        let budget: CGFloat = 1_300_000
        #endif
        let toHole = camera.holePos - camera.eye
        let dist = simd_length(toHole)
        let influence = camera.holeRs * 20
        var marchArea = area
        if dist > influence, camera.viewSize.height > 1 {
            let nativePerPoint = drawableSize.height / camera.viewSize.height
            let rPx = CGFloat(influence / max(dist, 1) * camera.halfHeightFocal) * nativePerPoint
            marchArea = min(area, .pi * rPx * rPx)
        }
        guard marchArea > budget else { return 1 }
        var s = sqrt(budget / marchArea)
        if idle { s = min(1, s * 2) }     // resting camera: spend frame time on crispness
        return max(0.3, (s * 10).rounded(.down) / 10)
    }

    private func render(in view: MTKView) {
        guard let queue, let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cb = queue.makeCommandBuffer() else { return }

        let now = CACurrentMediaTime()
        let dt = min(0.1, now - lastFrameTime)
        lastFrameTime = now
        discTime += dt

        bakeSkyIfNeeded(cb)
        // Near the hole many/all pixels are ray-marched, so scene + lens render into
        // internal textures at a budgeted pixel size and a final blit upscales to the
        // native drawable. All internal: the MTKView/layer never change scale (doing
        // that mid-flight corrupts SwiftUI's update graph and wedges the window).
        let moved = lastPose.map {
            simd_distance($0.eye, camera.eye) > camera.holeRs * 0.002 + 1e-5 ||
            simd_dot($0.fwd, camera.forward) < 0.999995
        } ?? true
        if moved {
            lastMoveTime = now
            lastPose = (camera.eye, camera.forward)
        }
        let scale = lensScale(drawableSize: view.drawableSize, idle: now - lastMoveTime > 0.6)
        let reduced = scale < 0.999
        let lensSize = CGSize(width: (view.drawableSize.width * scale).rounded(.down),
                              height: (view.drawableSize.height * scale).rounded(.down))
        if fpsLog {
            frameCount += 1
            let t = CACurrentMediaTime()
            if t - lastFPSLog > 2 {
                let dist = simd_distance(camera.eye, camera.holePos)
                print("METAL fps=\(String(format: "%.1f", Double(frameCount) / (t - lastFPSLog))) scale=\(scale) distPc=\(String(format: "%.1f", dist)) holeRs=\(camera.holeRs)")
                frameCount = 0
                lastFPSLog = t
            }
        }
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
            off.depthAttachment.storeAction = .store   // the lens pass reads it (foreground guard)
            off.depthAttachment.clearDepth = 1.0
            encodeSprites(cb, into: off)
            // Mip chain for the lens pass's blurred foreground-veil sample.
            if let blit = cb.makeBlitCommandEncoder() {
                blit.generateMipmaps(for: sceneColor)
                blit.endEncoding()
            }

            // 2) Lens pass: bends the scene around the hole, draws the shadow /
            //    photon ring / disc in place — into the drawable directly at full
            //    scale, or into lensOut when reduced.
            let lensTarget: MTLRenderPassDescriptor
            if reduced, let lensOut {
                lensTarget = MTLRenderPassDescriptor()
                lensTarget.colorAttachments[0].texture = lensOut
                lensTarget.colorAttachments[0].loadAction = .dontCare
                lensTarget.colorAttachments[0].storeAction = .store
                // The lens pipeline declares a depth32 attachment (it needs one when
                // targeting the drawable); Metal API validation asserts if the pass
                // has none. It can't be sceneDepth (the shader now SAMPLES that for
                // the foreground guard — attach + sample is a hazard), so a scratch
                // depth stands in as the bystander.
                lensTarget.depthAttachment.texture = lensScratchDepth
                lensTarget.depthAttachment.loadAction = .dontCare
                lensTarget.depthAttachment.storeAction = .dontCare
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
                enc.setFragmentTexture(sceneDepth, index: 2)
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
    /// Stops the display link while the map is invisible (a full-screen cover is
    /// up) — otherwise the full sprite scene keeps encoding at 60 fps behind the
    /// cover, pure battery/thermal burn on the screens users dwell on longest.
    var paused: Bool = false

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
        view.isPaused = paused
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        context.coordinator.update(scene: scene, version: sceneVersion, camera: camera)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        uiView.isPaused = paused
        context.coordinator.update(scene: scene, version: sceneVersion, camera: camera)
    }
}
