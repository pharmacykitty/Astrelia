#include <metal_stdlib>
using namespace metal;

// Gravitational lensing post-pass for the Galaxy Map — the real black hole at the
// centre of the Milky Way.
//
// The sprite scene renders to an offscreen texture; this full-screen pass bends
// every ray around Sgr A*. Rays passing near the hole march true Schwarzschild
// null geodesics (shadow, photon ring, multiple images, the procedural Doppler
// disc); rays passing wide get the closed-form weak-field deflection α ≈ 2·rs/b,
// so the bending decays smoothly to nothing instead of snapping off at a seam.
// Escaped rays sample the offscreen scene where they now point — the actual
// rendered galaxy lenses into Einstein rings — falling back to a baked equirect
// panorama (bake_* below) when the bent ray leaves the frame.
//
// Layout note: all-scalar uniforms (no float3!) so the Swift mirrors match
// byte-for-byte — a mismatch here is a device-only GPU hang.

struct LensUniforms {
    float4x4 viewProj;                            // camera-relative view-projection
    float rx, ry, rz, tanHalfW;                   // camera right basis + tan(fov_w/2)
    float ux, uy, uz, tanHalfH;                   // camera up basis + tan(fov_h/2)
    float fx, fy, fz, time;                       // camera forward + seconds (disc swirl)
    float hx, hy, hz, rs;                         // hole position (camera-relative, pc) + Schwarzschild radius (pc); rs ≤ 0 → passthrough
    float dnx, dny, dnz, diskInner;               // disc normal + inner radius (pc)
    float diskOuter, viewW, viewH, strength;      // disc outer (pc); view size; warp strength (fades when the influence disc subtends < ~a degree)
    float holeDepth, pad1, pad2, pad3;            // hole's log-depth for the foreground guard (< 0 → hole behind camera)
};

struct LensVSOut {
    float4 position [[position]];
    float2 uv;
};

// One full-screen triangle.
vertex LensVSOut lens_vertex(uint vid [[vertex_id]]) {
    float2 corner = float2((vid << 1) & 2, vid & 2);      // (0,0) (2,0) (0,2)
    LensVSOut out;
    out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(corner.x, 1.0 - corner.y);            // texture space, y down
    return out;
}

// ---- small helpers ----------------------------------------------------------

static float bh_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// Two-octave value noise — enough texture for gas bands without tanking the GPU.
static float bh_noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 s = f * f * (3.0 - 2.0 * f);
    return mix(mix(bh_hash(i),                    bh_hash(i + float2(1, 0)), s.x),
               mix(bh_hash(i + float2(0, 1)),     bh_hash(i + float2(1, 1)), s.x), s.y);
}

// Value noise periodic in x (period = whole number of lattice cells): for the
// disc's azimuthal gas bands, so the swirl connects seamlessly across ±π
// instead of leaving a radial seam.
static float bh_pnoise(float x, float period, float y) {
    float xi = floor(x), xf = x - xi;
    float yi = floor(y), yf = y - yi;
    float i0 = fmod(fmod(xi, period) + period, period);
    float i1 = fmod(i0 + 1.0, period);
    float sx = xf * xf * (3.0 - 2.0 * xf);
    float sy = yf * yf * (3.0 - 2.0 * yf);
    return mix(mix(bh_hash(float2(i0, yi)),       bh_hash(float2(i1, yi)), sx),
               mix(bh_hash(float2(i0, yi + 1.0)), bh_hash(float2(i1, yi + 1.0)), sx), sy);
}

// Equirectangular lookup for a world direction (equatorial frame, matching bake_vertex).
static float2 bh_equirect(float3 d) {
    return float2(atan2(d.y, d.x) / (2.0 * M_PI_F) + 0.5,
                  0.5 - asin(clamp(d.z, -1.0, 1.0)) / M_PI_F);
}

// Procedural thin accretion disc, shaded at a plane-crossing point (rs = 1 units).
// Radial temperature ramp, Keplerian orbital Doppler (beaming + colour shift),
// gravitational redshift, and a noise swirl advected at the orbital rate.
static float4 bh_disc(float3 xp, float3 n, float rd, float rIn, float rOut,
                      float time, float3 photonDir) {
    float3 e1 = normalize(cross(n, fabs(n.y) < 0.9 ? float3(0, 1, 0) : float3(1, 0, 0)));
    float3 e2 = cross(n, e1);
    float phi = atan2(dot(xp, e2), dot(xp, e1));

    float betaD = sqrt(0.5 / rd);                          // Keplerian v/c at rd (rs units)
    float3 tangent = normalize(cross(n, xp));              // prograde orbit
    float gam = 1.0 / sqrt(max(1e-4, 1.0 - betaD * betaD));
    float dop = 1.0 / (gam * (1.0 - betaD * dot(tangent, photonDir)));  // Doppler factor of the escaping photon
    float grav = sqrt(max(0.0, 1.0 - 1.0 / rd));           // gravitational redshift at emission

    // NASA-fire palette (SVS 14585): saturated red→orange, white only where the
    // Doppler boost earns it — never a pale cream wash.
    float t = saturate((rd - rIn) / max(0.01, rOut - rIn));
    float3 cHot  = float3(1.00, 0.90, 0.70);               // near-white inner rim
    float3 cMid  = float3(1.00, 0.45, 0.08);               // vivid orange
    float3 cCool = float3(0.70, 0.12, 0.02);               // deep red outer edge
    float3 col = t < 0.3 ? mix(cHot, cMid, t / 0.3) : mix(cMid, cCool, (t - 0.3) / 0.7);

    // Gas bands swirling at the (differential) Keplerian rate — inner laps outer.
    // Wide dynamic range: the banding carves real gaps (sky shows through between
    // filaments) instead of stacking into a featureless fog. Periodic in φ so the
    // pattern connects seamlessly across ±π (no radial seam).
    float omega = betaD / rd;                              // angular rate ∝ r^-1.5
    float phi01 = phi / (2.0 * M_PI_F) + 0.5;
    float band  = bh_pnoise(phi01 * 4.0 - time * omega * 6.7, 4.0, rd * 3.0);
    float band2 = bh_pnoise(phi01 * 8.0 - time * omega * 9.5 + 17.3, 8.0, rd * 7.0);
    // Low floor: NASA's streams have BLACK between them — the gaps must both dim
    // and transmit, or stacked lensed images fill everything to cream.
    float texture = 0.12 + 0.95 * band + 0.35 * band2;

    float radial = pow(rIn / rd, 1.7);                     // emissivity falls off outward (1.7: the outer sheet stays visible — 2.2 deleted everything past ~8 rs)
    // Beam cap: rays winding near the photon sphere cross the disc dozens of
    // times, EACH at maximum beaming — uncapped, stacked crossings accumulate
    // luminance in the hundreds and flood flat white.
    float dopC = clamp(dop, 0.25, 2.2);
    float beam = pow(dopC, 3.0);                           // beaming: white earns the centre only
    float3 shifted = col;
    shifted = mix(shifted * float3(1.0, 0.42, 0.22), shifted, saturate(dopC));               // receding limb reddens + dims
    shifted = mix(shifted, shifted * float3(1.16, 1.05, 0.90) + 0.20, saturate(dopC - 1.0)); // approaching limb whitens (warm, not blue)
    // NASA SVS 14585 palette check (frame-by-frame, 2026-07-31): their frames are
    // near-black with SATURATED red-orange fire in thin streams — white almost
    // nowhere. Gain down (1.6 → 1.05) and saturation up (1.3 → 1.45): the fire
    // stays fire, and the photon ring reads as the thin bright line it should be.
    float3 rgb = shifted * (radial * texture * beam) * grav * 1.05;
    float dlum = dot(rgb, float3(0.30, 0.55, 0.15));
    rgb = max(float3(0.0), mix(float3(dlum), rgb, 1.45));  // saturation push toward the fire

    // Optically THICK (NASA's disc shows a single surface, not stacked layers):
    // high alpha kills the transmittance after the first crossing or two, so the
    // fire keeps its swirl texture instead of layering into white.
    // The outer disc DISSOLVES: without this fade the dim outer expanse ended at
    // a hard rOut cutoff — a bounded, band-noise-textured slab whose elliptical
    // outline (and its lensed far-side domes) read as dark "bubbles" flanking
    // the shadow. Fire must thin into streams and then into nothing.
    float outerFade = 1.0 - smoothstep(0.55, 0.97, t);
    float alpha = saturate((0.10 + 0.90 * smoothstep(0.40, 1.15, texture)) * (1.0 - t * 0.85) * 1.4)
                * outerFade;
    return float4(rgb * outerFade, alpha);
}

fragment float4 lens_fragment(LensVSOut in [[stage_in]],
                              texture2d<float> sceneTex [[texture(0)]],
                              texture2d<float> skyTex [[texture(1)]],
                              depth2d<float> sceneDepthTex [[texture(2)]],
                              constant LensUniforms& u [[buffer(0)]]) {
    constexpr sampler smp(address::clamp_to_edge, filter::linear);

    if (u.rs <= 0.0) return sceneTex.sample(smp, in.uv);   // no hole in play — straight blit

    float3 fwd   = float3(u.fx, u.fy, u.fz);
    float3 right = float3(u.rx, u.ry, u.rz);
    float3 up    = float3(u.ux, u.uy, u.uz);
    float3 hp    = float3(u.hx, u.hy, u.hz);               // hole, camera at origin (pc)

    float2 ndc = float2(in.uv.x * 2.0 - 1.0, 1.0 - in.uv.y * 2.0);
    float3 dir = normalize(fwd + right * (ndc.x * u.tanHalfW) + up * (ndc.y * u.tanHalfH));

    float dAlong = dot(hp, dir);
    float3 cvec = dir * max(dAlong, 0.0) - hp;             // hole → closest approach
    float perp = length(cvec);
    float influence = u.rs * 20.0;                          // geodesic-march zone
    bool cameraInside = length(hp) < influence;

    float3 outDir = dir;                                    // escaped-ray direction
    float3 acc = float3(0.0);                               // accumulated disc light
    float trans = 1.0;                                      // transmittance to background
    bool captured = false;

    if (cameraInside || (dAlong > 0.0 && perp < influence)) {
        // ---- march the null geodesic in the hole frame, rs = 1 units ----
        float3 p = -hp / u.rs;
        float3 v = dir;
        float3 n = normalize(float3(u.dnx, u.dny, u.dnz));
        float h2 = length_squared(cross(p, v));             // conserved L²

        float rIn = u.diskInner / u.rs, rOut = u.diskOuter / u.rs;
        float escapeR = max(28.0, length(p) * 1.5);
        float prevSide = dot(p, n);

        for (int i = 0; i < 240; i++) {
            float r = length(p);
            if (r < 1.0) { captured = true; break; }
            if (r > escapeR && dot(p, v) > 0.0) break;      // escaped, heading out
            float dt = clamp(0.075 * r, 0.03, 2.2);         // adaptive step: fine near the hole
            v += (-1.5 * h2 / pow(r, 5.0)) * p * dt;        // Schwarzschild photon acceleration
            p += v * dt;
            float side = dot(p, n);
            if (side * prevSide < 0.0) {                    // crossed the disc plane
                float f = prevSide / (prevSide - side);
                float3 xp = p - v * dt * (1.0 - f);
                float rd = length(xp);
                if (rd > rIn && rd < rOut) {
                    float4 d = bh_disc(xp, n, rd, rIn, rOut, u.time, normalize(v));
                    acc += d.rgb * d.a * trans;
                    trans *= 1.0 - d.a;
                    if (trans < 0.02) break;                // effectively opaque
                }
            }
            prevSide = side;
        }
        outDir = normalize(v);
    } else if (dAlong > 0.0) {
        // Wide pass: closed-form weak-field deflection, continuous with the march
        // zone at b = influence and decaying as 1/b — no visible seam.
        float alpha = 2.0 * u.rs / max(perp, u.rs * 3.0);
        outDir = normalize(dir - (cvec / max(perp, 1e-5)) * alpha);
    }
    // Distance fade (device review 2026-08-10): from across the galaxy the
    // influence disc subtends well under a degree, yet the warp rippled at
    // full strength — bending content thousands of ly in FRONT of the hole.
    // Physically an Einstein ring at that distance is near sub-pixel; ease the
    // deflection out as the hole recedes. Captured rays keep their tiny true
    // shadow silhouette.
    if (u.strength < 0.999) outDir = normalize(mix(dir, outDir, max(u.strength, 0.0)));
    float bendRaw = 1.0 - dot(outDir, dir);               // how far the hole moved this ray

    // Background: the rendered galaxy sampled where the bent ray points, the baked
    // equirect sky when that leaves the frame.
    float3 bg = float3(0.0);
    float bgA = 0.0;
    if (!captured && trans > 0.02) {
        float screenW = 0.0;
        float4 clip = u.viewProj * float4(outDir * 60000.0, 1.0);
        if (clip.w > 0.0) {
            float2 suv = float2(clip.x / clip.w * 0.5 + 0.5, 0.5 - clip.y / clip.w * 0.5);
            float2 m = min(suv, 1.0 - suv);
            // Wide feather: at 0.015 the screen→bake handoff drew a visible
            // circle around the hole (the "bubble" edge) — blend over ~10% of
            // the frame instead so the two sources cross-fade invisibly.
            screenW = saturate(min(m.x, m.y) / 0.10);
            if (screenW > 0.0) {
                float4 s = sceneTex.sample(smp, suv);
                bg = s.rgb; bgA = s.a;
            }
        }
        // Only rays the hole actually BENT may fall back to the baked panorama —
        // an unbent edge pixel must keep its own screen sample, or the bake's warm
        // wash paints a border around the whole frame wherever the lens is active.
        // STRONGLY-bent rays must use the bake even when their deflected point is
        // still on screen: the screen sample re-images whatever sits beside the
        // hole (the nuclear swarm), double-imaging it into the flanking "bubbles"
        // — the bake is where near-hole content is culled, so only it can show
        // the clean distant sky the lens should bend.
        float bent = saturate(bendRaw * 400.0);
        float bakeW = max((1.0 - screenW) * bent, saturate(bendRaw * 25.0));
        if (bakeW > 0.001) {
            // Wrap longitude so rays crossing the panorama's ±π seam stay continuous.
            constexpr sampler wrapSmp(s_address::repeat, t_address::clamp_to_edge,
                                      filter::linear, mip_filter::linear);
            float2 buv = bh_equirect(outDir);
            // ANALYTIC mip level — never derivative-based: in the march zone
            // neighbouring rays diverge chaotically, so auto-lod flips per pixel
            // and sprays coloured grain. Strongly-lensed sectors compress many
            // images — a gentle blur matches that, kept granular so the lensed
            // cluster reads as warped stars, not a blob.
            float lodF = clamp(saturate(bendRaw * 3.0), 0.0, 6.0);
            // Tangentially SHEARED base sample: a lensed image is stretched into
            // an arc around the hole, and without the stretch the (physically
            // real) double image of the galaxy's radiant core reads as two round
            // bubbles beside the shadow — the original sin of this whole look.
            // Three taps rotated about the hole axis, arc length ∝ bend.
            float4 b;
            {
                float3 axisB = normalize(hp);
                float deltaB = min(0.05, bendRaw * 0.55);
                if (deltaB > 0.002) {                      // sheared arcs near the ring only
                    b = float4(0.0);
                    for (int k = -2; k <= 2; k++) {
                        float3 dB = normalize(outDir + cross(axisB, outDir) * (deltaB * float(k)));
                        b += skyTex.sample(wrapSmp, bh_equirect(dB), level(lodF));
                    }
                    b *= 1.0 / 5.0;
                } else {                                   // weak bend: one tap is identical
                    b = skyTex.sample(wrapSmp, buv, level(lodF));
                }
            }
            // Strongly-bent rays get an unsharp star split: sampling only the
            // blurred bake rendered the lensed region as a flat dark disc around
            // the hole ("a bubble") — lensing should show the sky's own stars,
            // warped. Coarse mip = the glow; fine-minus-coarse = the POINT STARS.
            float starGate = saturate(bendRaw * 40.0);
            float3 bStars = float3(0.0);
            if (starGate > 0.001) {
                float lodStar = clamp(max(lodF * 0.6, 1.0), 1.0, 2.5);   // soft dots, never confetti
                float3 coarse = skyTex.sample(wrapSmp, buv, level(lodStar + 3.0)).rgb;
                // Tangential 3-tap: rotate the sample direction slightly around
                // the hole axis, arc length growing with the bend — stars near
                // the Einstein ring stretch into short tangential ARCS, the
                // signature strong-lensing cue.
                float3 axisH = normalize(hp);
                float delta = min(0.035, bendRaw * 0.35);
                float3 acc3;
                if (delta > 0.002) {
                    acc3 = float3(0.0);
                    for (int k = -1; k <= 1; k++) {
                        float3 d2 = normalize(outDir + cross(axisH, outDir) * (delta * float(k)));
                        acc3 += skyTex.sample(wrapSmp, bh_equirect(d2), level(lodStar)).rgb;
                    }
                    acc3 *= 1.0 / 3.0;
                } else {
                    acc3 = skyTex.sample(wrapSmp, buv, level(lodStar)).rgb;
                }
                bStars = max(acc3 - coarse, 0.0);
                // Compact bright bake patches (nebulae, the nucleus) survive the
                // unsharp split as big "stars" and gain into pale smears. Real
                // point stars sit on a DARK neighbourhood (coarse ≈ 0); suppress
                // the detail wherever the neighbourhood itself is bright, and cap
                // the per-pixel luminance for whatever slips through.
                float suppress = saturate(1.0 - dot(coarse, float3(0.30, 0.55, 0.15)) * 5.0);
                bStars *= suppress;
                float slum0 = dot(bStars, float3(0.30, 0.55, 0.15));
                bStars *= min(1.0, 0.45 / max(slum0, 1e-4));
            }
            // The bake resolves individual stars but under-samples the soft bulge
            // wash (its sprites shrink to true angular size); add the nucleus glow
            // procedurally — a warm band hugging the galactic plane — so strongly
            // bent rays blend seamlessly with the on-screen haze.
            float3 n = normalize(float3(u.dnx, u.dny, u.dnz));
            float planeDist = dot(outDir, n);
            // The Milky Way as a THIN, dusty, textured band: kept to a faint
            // trace — the real baked Milky Way carries the look; at full weight
            // this procedural great-circle ribbon drew a hard seam-like line
            // across the whole lens region.
            float bandProfile = exp(-planeDist * planeDist * 55.0);
            float bandTex = 0.55 + 0.45 * bh_noise(float2(atan2(outDir.y, outDir.x) * 6.0,
                                                          planeDist * 14.0));
            b.rgb += float3(0.66, 0.58, 0.48) * (0.024 * bandProfile * bandTex);
            float haze = exp(-planeDist * planeDist * 5.0) * 0.05
                       * saturate((length(hp) / u.rs - 5.0) / 15.0);
            b.rgb += float3(1.0, 0.82, 0.55) * haze;
            if (starGate > 0.001) {
                // The lensed field shows its stars — a gentle lift only: the
                // camera-centred bake already carries the real sky, and a strong
                // gain turned dense cluster regions into cream blobs.
                float slum = dot(bStars, float3(0.30, 0.55, 0.15));
                b.rgb += bStars * 1.15 * starGate;
                b.a = max(b.a, saturate(slum * 1.5) * starGate * 0.6);
            }
            // Magnification glow, kept SUBTLE: brightening smooth fog paints
            // glossy dome rims (bulging-object read) — lensing only reads on
            // structure.
            b.rgb *= 1.0 + 0.2 * saturate(bendRaw * 20.0);
            b.a = max(b.a, bandProfile * 0.5);
            bg = mix(bg, b.rgb, bakeW);
            bgA = mix(bgA, b.a, bakeW);
        }
    }

    float3 col = acc + bg * trans;
    // The shadow must be a solid black ball (not the UI gradient leaking through);
    // the disc adds its own coverage on top of whatever background survives.
    float a = captured ? 1.0 : max(bgA * trans, saturate(1.0 - trans));

    // Un-lensed foreground veil. The lens treats every scene pixel as living
    // BEHIND the hole, but the bulge's warm fog fills the space in front of it
    // too — deflecting that light punched a dark "bubble" in the fog around the
    // whole influence region. Re-composite a blurred sample of this pixel's
    // ORIGINAL screen position over content-replaced rays (incl. a faint wash
    // over the shadow — the fog is in front of it).
    {
        constexpr sampler veilSmp(address::clamp_to_edge, filter::linear, mip_filter::linear);
        // The shadow keeps only a TRACE of fog (0.22): at half strength it read
        // as a tan glass ball — the black anchor is what stops the lens region
        // reading as a solid object. Bent rays get barely any: the camera-centred
        // bake already carries the real foreground fog, and stacking the veil on
        // top double-counts it.
        float veilGate = max(saturate(bendRaw * 30.0) * 0.25, captured ? 0.22 : 0.0);
        float veilW = 0.5 * veilGate;
        if (veilW > 0.001) {
            float3 veil = sceneTex.sample(veilSmp, in.uv, level(4.0)).rgb;
            col += veil * veilW;
            a = max(a, saturate(dot(veil, float3(0.30, 0.55, 0.15)) * 2.0) * veilW);
        }
    }

    float4 res = float4(col, a);
    // FOREGROUND GUARD (device review 2026-08-10): the lens treats every scene
    // pixel as living behind the hole, so a nebula thousands of light-years in
    // FRONT of it got bent and hole-punched (California Nebula over Sgr A*).
    // The occluder pass writes real depth for opaque landmark cores — where the
    // scene is genuinely nearer than the hole, the un-warped scene pixel wins
    // the frame back. (Log-depth is monotonic: smaller = nearer.)
    if (u.holeDepth > 0.0) {
        float sceneD = sceneDepthTex.sample(smp, in.uv);
        float fg = 1.0 - smoothstep(u.holeDepth * 0.986, u.holeDepth, sceneD);
        if (fg > 0.001) {
            float4 orig = sceneTex.sample(smp, in.uv);
            res.rgb = mix(res.rgb, orig.rgb, fg);
            res.a = mix(res.a, orig.a, fg);
        }
    }
    // Blue-noise-ish dither: long smooth ramps posterize on the 8-bit
    // reduced-res target without it.
    res.rgb += (bh_hash(in.uv * float2(u.viewW, u.viewH) + fract(u.time * 0.37) * 61.0) - 0.5)
               * (2.0 / 255.0);
    return res;
}

// ---- Equirect sky bake ------------------------------------------------------
//
// Renders the sprite scene (additive light only) into a 2048×1024 equirectangular
// panorama as seen FROM THE CAMERA (re-baked as it moves), so bent rays that
// leave the screen sample the same sky the screen shows — one continuous
// background, no content jump at the handoff. Self-contained: no handedness or
// seam logic beyond clamping (sprites straddling the longitude seam are
// accepted losses).

struct BakeUniforms {
    float ox, oy, oz, skipRadius;   // bake origin = CAMERA (world pc); cull sprites closer than this
    float hx, hy, hz, holeSkip;     // hole position + beacon cull radius (its sprite glow must not double into the lensed sky)
    float texW, texH, coreSkip, pad1; // soft world-scale glow within coreSkip of the hole stays OUT of the lensed sky
};

struct SpriteInstanceB {            // matches SpriteInstance in GalaxyShaders.metal
    float px, py, pz;
    float radius;
    float r, g, b, a;
    float minPixel, maxPixel;
    float softness;
    float mode;
    // MUST stay byte-identical with the main shader's 16-float layout: when the
    // wisp fields were added there, this copy's stale 12-float stride scrambled
    // the lens's offscreen scene pass into giant white lobes around Sgr A*.
    // The bake pass renders these sprites round (no stretch) — at the lensed
    // far-field's scale the anisotropy is sub-pixel anyway.
    float dx, dy, dz;
    float aspect;
};

struct BakeVSOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float softness;
};

constant float2 kBakeCorners[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };

vertex BakeVSOut bake_vertex(uint vid [[vertex_id]],
                             uint iid [[instance_id]],
                             const device SpriteInstanceB* inst [[buffer(0)]],
                             constant BakeUniforms& u [[buffer(1)]]) {
    SpriteInstanceB s = inst[iid];
    BakeVSOut out;
    out.uv = kBakeCorners[vid];
    out.color = float4(s.r, s.g, s.b, s.a);
    out.softness = s.softness;

    float3 rel = float3(s.px, s.py, s.pz) - float3(u.ox, u.oy, u.oz);
    float dist = length(rel);
    float holeDist = length(float3(s.px, s.py, s.pz) - float3(u.hx, u.hy, u.hz));
    // Cull: sprites hugging the camera, and EVERYTHING near the hole (beacon,
    // core glow, the nuclear star swarm — u.coreSkip). Any compact content
    // sitting behind the hole double-images into two lobes flanking the shadow
    // — "the two bubbles" — whether it's smooth glow or crisp grain. The lensed
    // sky shows only the DISTANT background (stars, arms, dust ribbon), which
    // bends into clean arcs; the direct un-lensed view keeps all the local
    // content.
    if (dist < u.skipRadius || holeDist < u.coreSkip) {
        out.position = float4(2.0, 2.0, 2.0, 1.0);
        return out;
    }
    float2 uv = bh_equirect(rel / dist);

    // Angular size → bake pixels (px per radian = texW / 2π), with the sprite's
    // own pixel clamps (floored so faint distant stars survive at panorama scale).
    float pxPerRad = u.texW / (2.0 * M_PI_F);
    float worldPx = s.radius * pxPerRad / dist;
    float screenPx = s.radius / dist;
    float px = clamp(s.mode < 0.5 ? worldPx : screenPx, max(s.minPixel, 1.5), s.maxPixel);

    float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    ndc += kBakeCorners[vid] * (px / (float2(u.texW, u.texH) * 0.5));
    out.position = float4(ndc, 0.0, 1.0);
    return out;
}

// Identical shading to sprite_additive, so the panorama looks like the scene.
fragment float4 bake_fragment(BakeVSOut in [[stage_in]]) {
    float r = length(in.uv);
    float exponent = mix(0.25, 2.2, in.softness);
    float mask = pow(saturate(1.0 - r), exponent);
    float a = in.color.a * mask;
    return float4(in.color.rgb * a, a);
}

// Upscale blit: the lens pass renders at reduced resolution into an internal
// texture (a native-res geodesic march per pixel is unaffordable when the
// influence region fills the frame); this stretches it onto the full drawable.
// Deliberately dumb — bilinear soft.
fragment float4 blit_fragment(LensVSOut in [[stage_in]],
                              texture2d<float> src [[texture(0)]]) {
    constexpr sampler smp(address::clamp_to_edge, filter::linear);
    return src.sample(smp, in.uv);
}
