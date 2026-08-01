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

// DiveChannel + DivePhysics (the free-fall integration the renderer runs while
// diving) live in BlackHoleDive.swift.

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
    // For the renderer-side dive camera (it rebuilds the projection while falling).
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
    // The disc's animation clock. Advanced per frame with a dive-dependent warp
    // (the infalling observer sees the outside universe fast-forward), accumulated
    // so the swirl phase never jumps when the rate changes.
    private var warpedTime: Double = 0
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
    // Debug (`-fpsLog`): print frame rate + lens scale every ~2 s.
    private let fpsLog = ProcessInfo.processInfo.arguments.contains("-fpsLog")
    private var frameCount = 0
    private var lastFPSLog = CACurrentMediaTime()
    private var lastDump: CFTimeInterval = 0
    private var dumpIndex = 0

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

    // Free-fall state, integrated per display-link frame from the handoff's actual
    // position/velocity (DivePhysics). Renderer-owned: the dive must not depend on
    // a SwiftUI render to start or advance.
    private var diveActive = false
    private var divePos = SIMD3<Float>(0, 0, 0)
    private var diveVel = SIMD3<Float>(0, 0, 0)
    private var diveForward = SIMD3<Float>(0, 0, -1)
    private var diveRoll: Float = 0
    private var diveOrbit: Float = 0                      // spiral angle — infall has angular momentum
    private var diveTilt = SIMD3<Float>(0, 0, 0)          // composition: hole off-axis, disc in frame
    private(set) var diveNarrativeR: Float = .infinity   // rs units

    private func applyDiveCamera(dt: Float) {
        guard camera.holeRs > 0, let ch = diveChannel, ch.start != nil else {
            diveActive = false
            return
        }
        let rs = camera.holeRs
        if !diveActive {
            // Seamless handoff: continue from exactly where free flight was, the
            // way it was moving — no repositioning, no aim cut.
            diveActive = true
            divePos = ch.entryEye
            diveVel = ch.entryVelocity
            let maxEntry = DivePhysics.maxEntrySpeedRsPerS * rs
            if simd_length(diveVel) > maxEntry { diveVel = simd_normalize(diveVel) * maxEntry }
            diveForward = ch.entryForward
            diveRoll = 0
            diveOrbit = 0
            diveNarrativeR = simd_distance(ch.entryEye, camera.holePos) / rs
            // In portrait, a dead-centre shadow outgrows the screen and the fall
            // shows nothing but black. Tilt the composition toward the disc plane
            // (whichever side we're on) so the shadow's fiery boundary and the
            // disc sweep stay in frame — the NASA-shot framing.
            let n = simd_normalize(camera.diskNormal)
            let side: Float = simd_dot(ch.entryEye - camera.holePos, n) >= 0 ? 1 : -1
            // Tilt AWAY from the disc plane (NASA-mound framing): the hole and its
            // fiery boundary sit low in frame while the upper frame opens to black
            // sky, stars, and the lensed Milky Way band — the universe warping.
            diveTilt = n * side * 0.55
        }

        var toHole = camera.holePos - divePos
        var r = simd_length(toHole) / rs
        let inward = r > 1e-4 ? simd_normalize(toHole) : SIMD3<Float>(0, 0, 1)

        if diveNarrativeR > 1, r > 1 {
            // Gravity owns the fall; the entry velocity just seasons the approach.
            diveVel += inward * (DivePhysics.gravity / max(r * r, 0.2)) * rs * dt
            let maxFall = DivePhysics.maxFallSpeedRsPerS * rs
            if simd_length(diveVel) > maxFall { diveVel = simd_normalize(diveVel) * maxFall }
            divePos += diveVel * dt
            toHole = camera.holePos - divePos
            r = simd_length(toHole) / rs
            diveNarrativeR = r
        } else {
            // Inside (once crossed, forever): nothing outside the horizon is
            // renderable from within (every ray terminates), so the render radius
            // holds just outside while the narrative radius runs down the real
            // ~12.8 s to the singularity.
            diveNarrativeR = max(DivePhysics.endRadiusRs,
                                 min(diveNarrativeR, 1) - DivePhysics.interiorRateRsPerS * dt)
            divePos = camera.holePos - inward * (1.02 * rs)
            diveVel = inward * (0.05 * rs)   // a crawl, so the view stays gently alive
        }
        ch.currentRRs = Double(diveNarrativeR)
        if diveNarrativeR <= DivePhysics.endRadiusRs + 0.001 { ch.finished = true }

        // Infall has angular momentum: the render pose spirals around the hole
        // (circling the drain, faster with β), so the disc and ring stream past
        // continuously instead of the view freezing at the render floor.
        let beta = Float(DivePhysics.beta(atRs: Double(max(r, 1))))
        let motionScale: Float = ch.reduceMotion ? 0.35 : 1
        diveOrbit += (0.10 + 0.45 * beta) * dt * motionScale

        let axisN = simd_normalize(camera.diskNormal)
        let renderR = max(diveNarrativeR, DivePhysics.renderFloorRs)
        let radial0 = -inward
        let cosO = cos(diveOrbit), sinO = sin(diveOrbit)
        let radial = radial0 * cosO + simd_cross(axisN, radial0) * sinO
                   + axisN * simd_dot(axisN, radial0) * (1 - cosO)
        let renderPos = camera.holePos + simd_normalize(radial) * (renderR * rs)
        let inwardR = simd_normalize(camera.holePos - renderPos)

        // Look where you're falling (eased), drifting toward the disc-plane
        // composition as the fall deepens, with a slow speed-scaled roll.
        // (A look-back flip was tried here 2026-07-31 and read as ZOOMING AWAY —
        // compression of the sky toward the view centre is optically identical
        // to receding. The plunge stays forward; the shader's aperture now
        // magnifies the forward view instead: the tunnel, not the dome.)
        let tiltRamp = max(0, min(1, (6 - diveNarrativeR) / 2.5))
        let aim = simd_normalize(inwardR + diveTilt * tiltRamp)
        let ease = min(1, dt / 1.2)
        var forward = diveForward + (aim - diveForward) * ease
        forward = simd_length_squared(forward) < 1e-8 ? inwardR : simd_normalize(forward)
        diveForward = forward

        if !ch.reduceMotion { diveRoll += (0.03 + 0.12 * beta) * dt }

        camera.dive = DivePhysics.stage(atRs: Double(diveNarrativeR), reduceMotion: ch.reduceMotion)

        var side = simd_cross(forward, SIMD3<Float>(0, 1, 0))
        side = simd_length(side) < 1e-4 ? SIMD3(1, 0, 0) : simd_normalize(side)
        var up = simd_cross(side, forward)
        if diveRoll != 0 {
            let c = cos(diveRoll), s = sin(diveRoll)
            let rolledSide = side * c + simd_cross(forward, side) * s
            let rolledUp = up * c + simd_cross(forward, up) * s
            side = simd_normalize(rolledSide)
            up = simd_normalize(rolledUp)
        }

        // Camera-relative look-at (eye at origin) + perspective, matching makeCamera.
        let f = forward
        let view = simd_float4x4(columns: (
            SIMD4(side.x, up.x, -f.x, 0),
            SIMD4(side.y, up.y, -f.y, 0),
            SIMD4(side.z, up.z, -f.z, 0),
            SIMD4(0, 0, 0, 1)
        ))
        // Speed-scaled FOV widen: more of the ring fits the narrow portrait frame
        // as the fall deepens.
        let fov = camera.fovY * (1 + 0.35 * beta * (ch.reduceMotion ? 0.5 : 1))
        camera.tanHalfH = tan(fov * 0.5)
        camera.tanHalfW = camera.tanHalfH * max(camera.aspect, 1e-4)
        let yScale = 1 / tan(fov * 0.5)
        let xScale = yScale / max(camera.aspect, 1e-4)
        let zScale: Float = 200000 / (0.05 - 200000)
        let projection = simd_float4x4(columns: (
            SIMD4(xScale, 0, 0, 0),
            SIMD4(0, yScale, 0, 0),
            SIMD4(0, 0, zScale, -1),
            SIMD4(0, 0, zScale * 0.05, 0)
        ))
        camera.viewProj = projection * view
        // The pose floors at the visualization radius and rides the spiral; the
        // fall and the narrative continue beneath it.
        camera.eye = renderPos
        camera.forward = forward
        camera.right = side
        camera.up = up

        uniforms.viewProj = camera.viewProj
        uniforms.ex = renderPos.x; uniforms.ey = renderPos.y; uniforms.ez = renderPos.z
    }

    private func makeLensUniforms() -> LensUniforms {
        let c = camera
        let hp = c.holePos - c.eye        // camera-relative, like everything GPU-side
        return LensUniforms(viewProj: c.viewProj,
                            rx: c.right.x, ry: c.right.y, rz: c.right.z, tanHalfW: c.tanHalfW,
                            ux: c.up.x, uy: c.up.y, uz: c.up.z, tanHalfH: c.tanHalfH,
                            fx: c.forward.x, fy: c.forward.y, fz: c.forward.z,
                            time: Float(warpedTime),
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
        // Skip only the hole's own beacon. The nucleus glow STAYS in the panorama:
        // the lensed sky must match the warm haze the screen shows around it, or
        // the strongly-bent sectors read as alien dark bubbles. The dive darkens
        // the sky later via the interior aperture fade instead.
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
        applyDiveCamera(dt: Float(dt))
        warpedTime += dt * (diveActive ? DivePhysics.timeWarp(atRs: Double(diveNarrativeR)) : 1)

        bakeSkyIfNeeded(cb)
        // Near the hole many/all pixels are ray-marched, so scene + lens render into
        // internal textures at a budgeted pixel size and a final blit upscales to the
        // native drawable. All internal: the MTKView/layer never change scale (doing
        // that mid-flight corrupts SwiftUI's update graph and wedges the window).
        let diving = diveActive
        let moved = lastPose.map {
            simd_distance($0.eye, camera.eye) > camera.holeRs * 0.002 + 1e-5 ||
            simd_dot($0.fwd, camera.forward) < 0.999995
        } ?? true
        if moved || diving {
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
                // The lens pipeline declares a depth32 attachment (it needs one when
                // targeting the drawable); Metal API validation asserts if the pass
                // has none, so attach the same-size scene depth as a bystander.
                lensTarget.depthAttachment.texture = sceneDepth
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

            if dumpFrames, reduced, diveActive, let lensOut,
               CACurrentMediaTime() - lastDump > 0.7 {
                lastDump = CACurrentMediaTime()
                // Sub-second cadence + a monotonically unique tag (radius repeats
                // once the narrative floors) so a whole dive can be reviewed as a
                // filmstrip, not 2.5 s keyframes.
                dumpIndex += 1
                let tag = String(format: "%03d_r%04.2f", dumpIndex, diveNarrativeR)
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
    /// Stops the display link while the map is invisible (a full-screen cover is
    /// up) — otherwise the full sprite scene keeps encoding at 60 fps behind the
    /// cover, pure battery/thermal burn on the screens users dwell on longest.
    var paused: Bool = false
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
        view.isPaused = paused
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        context.coordinator.diveChannel = diveChannel
        context.coordinator.update(scene: scene, version: sceneVersion, camera: camera)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        uiView.isPaused = paused
        context.coordinator.diveChannel = diveChannel
        context.coordinator.update(scene: scene, version: sceneVersion, camera: camera)
    }
}
