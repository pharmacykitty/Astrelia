#include <metal_stdlib>
using namespace metal;

// Gravitational lensing post-pass for the Galaxy Map — the real black hole at the
// centre of the Milky Way (design of record: docs/black-hole-dive.md).
//
// The sprite scene renders to an offscreen texture; this full-screen pass bends
// every ray around Sgr A*. Rays passing near the hole march true Schwarzschild
// null geodesics (shadow, photon ring, multiple images, the procedural Doppler
// disc); rays passing wide get the closed-form weak-field deflection α ≈ 2·rs/b,
// so the bending decays smoothly to nothing instead of snapping off at a seam.
// Escaped rays sample the offscreen scene where they now point — the actual
// rendered galaxy lenses into Einstein rings — falling back to a baked equirect
// panorama (bake_* below) when the bent ray leaves the frame. Dive uniforms
// (beta/aperture/spaghetti/redshift/flash) stage the plunge; Swift sequences the
// beats, the shader stays dumb.
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
    float diskOuter, beta, bakeMix, aperture;     // disc outer (pc); infall v/c; equirect blend; universe-collapse
    float spaghetti, redshiftG, flash, discBoost; // tidal stretch; global redshift; final flash; disc flare
    float viewW, viewH, pad0, pad1;
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

// Relativistic aberration: as β→1 the whole sky crowds toward the travel axis.
static float3 bh_aberrate(float3 d, float3 axis, float beta) {
    float c = dot(d, axis);
    float3 perp = d - c * axis;
    float pl = length(perp);
    float cNew = (c + beta) / (1.0 + beta * c);
    float s = sqrt(max(0.0, 1.0 - cNew * cNew));
    return normalize(axis * cNew + (pl > 1e-5 ? perp / pl : float3(0)) * s);
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
                      float time, float3 photonDir, float boost) {
    float3 e1 = normalize(cross(n, fabs(n.y) < 0.9 ? float3(0, 1, 0) : float3(1, 0, 0)));
    float3 e2 = cross(n, e1);
    float phi = atan2(dot(xp, e2), dot(xp, e1));

    float betaD = sqrt(0.5 / rd);                          // Keplerian v/c at rd (rs units)
    float3 tangent = normalize(cross(n, xp));              // prograde orbit
    float gam = 1.0 / sqrt(max(1e-4, 1.0 - betaD * betaD));
    float dop = 1.0 / (gam * (1.0 - betaD * dot(tangent, photonDir)));  // Doppler factor of the escaping photon
    float grav = sqrt(max(0.0, 1.0 - 1.0 / rd));           // gravitational redshift at emission

    float t = saturate((rd - rIn) / max(0.01, rOut - rIn));
    float3 cHot  = float3(1.00, 0.985, 0.95);              // white-hot inner rim
    float3 cMid  = float3(1.00, 0.55, 0.16);               // amber
    float3 cCool = float3(0.55, 0.14, 0.03);               // dim red outer edge
    float3 col = t < 0.42 ? mix(cHot, cMid, t / 0.42) : mix(cMid, cCool, (t - 0.42) / 0.58);

    // Gas bands swirling at the (differential) Keplerian rate — inner laps outer.
    // Wide dynamic range: the banding carves real gaps (sky shows through between
    // filaments) instead of stacking into a featureless fog.
    float omega = betaD / rd;                              // angular rate ∝ r^-1.5
    float band  = bh_noise(float2(phi * 2.6 - time * omega * 42.0, rd * 2.3));
    float band2 = bh_noise(float2(phi * 6.5 - time * omega * 60.0 + 17.3, rd * 5.7));
    float texture = 0.30 + 0.85 * band + 0.35 * band2;

    float radial = pow(rIn / rd, 2.2);                     // emissivity falls off outward
    float beam = pow(clamp(dop, 0.22, 3.0), 3.0);          // relativistic beaming
    float3 shifted = col;
    shifted = mix(shifted * float3(1.0, 0.42, 0.22), shifted, saturate(dop));               // receding limb reddens + dims
    shifted = mix(shifted, shifted * float3(0.72, 0.86, 1.18) + 0.30, saturate(dop - 1.0)); // approaching limb blue-whitens
    float3 rgb = shifted * (radial * texture * beam) * grav * 3.2 * (1.0 + boost * 2.0);

    float alpha = saturate((0.10 + 0.90 * smoothstep(0.40, 1.15, texture)) * (1.0 - t * 0.92) * 0.85);
    return float4(rgb, alpha);
}

// Post effects shared by every pixel (dive staging).
static float4 bh_post(float3 col, float a, float3 dir, float3 fwd, constant LensUniforms& u) {
    if (u.beta > 0.001) {                                  // Doppler headlight: ahead brightens/blue-shifts
        float ahead = saturate(dot(dir, fwd));
        float boost = 1.0 + u.beta * 1.1 * ahead * ahead * ahead;
        col *= boost * mix(float3(1.0), float3(0.86, 0.94, 1.18), u.beta * ahead * 0.6);
    }
    if (u.redshiftG > 0.001) {                             // everything reddens and dies
        float lum = dot(col, float3(0.30, 0.55, 0.15));
        col = mix(col, lum * float3(1.0, 0.28, 0.10), u.redshiftG);
        col *= 1.0 - u.redshiftG;                          // → true black at 1.0
    }
    // Speed-gated soft knee: mid-plunge the stacked boosts (disc images × beaming ×
    // headlight) clip the whole frame to white — roll the wash off filmically while
    // the photon ring stays white-hot. Inactive when parked (the static hole keeps
    // its crisp look).
    float knee = saturate(u.beta * 1.5);
    if (knee > 0.001) {
        float lum = dot(col, float3(0.30, 0.55, 0.15));
        col = mix(col, col / (1.0 + 0.45 * lum), knee);
    }
    if (u.flash > 0.001) {                                 // the final white-out
        col = mix(col, float3(1.35), u.flash);
        a = max(a, u.flash);
    }
    return float4(col, a);
}

fragment float4 lens_fragment(LensVSOut in [[stage_in]],
                              texture2d<float> sceneTex [[texture(0)]],
                              texture2d<float> skyTex [[texture(1)]],
                              constant LensUniforms& u [[buffer(0)]]) {
    constexpr sampler smp(address::clamp_to_edge, filter::linear);

    if (u.rs <= 0.0) return sceneTex.sample(smp, in.uv);   // no hole in play — straight blit

    float3 fwd   = float3(u.fx, u.fy, u.fz);
    float3 right = float3(u.rx, u.ry, u.rz);
    float3 up    = float3(u.ux, u.uy, u.uz);
    float3 hp    = float3(u.hx, u.hy, u.hz);               // hole, camera at origin (pc)

    float2 ndc = float2(in.uv.x * 2.0 - 1.0, 1.0 - in.uv.y * 2.0);

    // Tidal spaghettification: stretch the image radially along the hole axis.
    if (u.spaghetti > 0.001) {
        float4 hc = u.viewProj * float4(hp, 1.0);
        float2 hndc = hc.w > 0.001 ? hc.xy / hc.w : float2(0.0);
        float2 dv = ndc - hndc;
        float stretch = 1.0 + u.spaghetti * 5.0 * exp(-length(dv) * 1.1);
        ndc = hndc + dv / stretch;
    }

    float3 dir = normalize(fwd + right * (ndc.x * u.tanHalfW) + up * (ndc.y * u.tanHalfH));
    // Relativistic aberration, INVERSE map: for each screen direction in the
    // infalling frame, find the rest-frame ray it came from (negative β). The sky
    // crowds bright toward the travel axis and the shadow shrinks. Kept at 0.4×β:
    // at full strength the shrink outruns the camera's fall and the hole appears
    // to RECEDE mid-plunge — engulfment must win the tug-of-war.
    if (u.beta > 0.001) dir = bh_aberrate(dir, fwd, -u.beta * 0.4);

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
                    float4 d = bh_disc(xp, n, rd, rIn, rOut, u.time, normalize(v), u.discBoost);
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

    // Background: the rendered galaxy sampled where the bent ray points, the baked
    // equirect sky when that leaves the frame (or during a dive, when the whole
    // aberrated sky must come from the bake).
    float3 bg = float3(0.0);
    float bgA = 0.0;
    if (!captured && trans > 0.02) {
        float screenW = 0.0;
        float4 clip = u.viewProj * float4(outDir * 60000.0, 1.0);
        if (clip.w > 0.0) {
            float2 suv = float2(clip.x / clip.w * 0.5 + 0.5, 0.5 - clip.y / clip.w * 0.5);
            // Fade the screen-space contribution out near the frame edge so the
            // handoff to the baked panorama is invisible.
            float2 m = min(suv, 1.0 - suv);
            screenW = saturate(min(m.x, m.y) / 0.04);
            if (screenW > 0.0) {
                float4 s = sceneTex.sample(smp, suv);
                bg = s.rgb; bgA = s.a;
            }
        }
        float bakeW = max(1.0 - screenW, u.bakeMix);
        if (bakeW > 0.001) {
            float4 b = skyTex.sample(smp, bh_equirect(outDir));
            // The bake resolves individual stars but under-samples the soft bulge
            // wash (its sprites shrink to true angular size); add the nucleus glow
            // procedurally — a warm band hugging the galactic plane — so strongly
            // bent rays blend seamlessly with the on-screen haze.
            float3 n = normalize(float3(u.dnx, u.dny, u.dnz));
            float planeDist = dot(outDir, n);
            float band = exp(-planeDist * planeDist * 5.0);
            // Fades as the plunge accelerates: the streaking stars and the disc
            // carry the drama; a bright ambient would white the whole frame out.
            float calm = 1.0 - 0.8 * saturate(u.beta / 0.7);
            float3 bulge = float3(1.0, 0.82, 0.55) * (0.30 * band + 0.05) * calm;
            b.rgb += bulge;
            b.a = max(b.a, (0.75 * band + 0.18) * calm);
            bg = mix(bg, b.rgb, bakeW);
            bgA = mix(bgA, b.a, bakeW);
        }
        bg *= 1.0 - u.aperture;                             // the outside universe closes down
        bgA *= 1.0 - u.aperture;
    }

    float3 col = acc + bg * trans;
    // The shadow must be a solid black ball (not the UI gradient leaking through);
    // the disc adds its own coverage on top of whatever background survives.
    float a = captured ? 1.0 : max(bgA * trans, saturate(1.0 - trans));

    return bh_post(col, a, dir, fwd, u);
}

// ---- Equirect sky bake ------------------------------------------------------
//
// Renders the sprite scene (additive light only) into a 2048×1024 equirectangular
// panorama as seen from the black hole, so bent rays that leave the screen still
// have the real galaxy to sample. Self-contained: no handedness or seam logic
// beyond clamping (sprites straddling the longitude seam are accepted losses).

struct BakeUniforms {
    float hx, hy, hz, skipRadius;   // bake origin (world pc); cull sprites closer than this
    float texW, texH, pad0, pad1;
};

struct SpriteInstanceB {            // matches SpriteInstance in GalaxyShaders.metal
    float px, py, pz;
    float radius;
    float r, g, b, a;
    float minPixel, maxPixel;
    float softness;
    float mode;
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

    float3 rel = float3(s.px, s.py, s.pz) - float3(u.hx, u.hy, u.hz);
    float dist = length(rel);
    if (dist < u.skipRadius) {                    // too close to the hole (its own beacon)
        out.position = float4(2.0, 2.0, 2.0, 1.0);
        return out;
    }
    float2 uv = bh_equirect(rel / dist);

    // Angular size → bake pixels (px per radian = texW / 2π), with the sprite's
    // own pixel clamps (floored so faint distant stars survive at panorama scale).
    float pxPerRad = u.texW / (2.0 * M_PI_F);
    float worldPx = s.radius * pxPerRad / dist;
    float screenPx = s.radius / dist;
    float px = clamp(s.mode < 0.5 ? worldPx : screenPx, max(s.minPixel, 1.1), s.maxPixel);

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
// texture (a native-res geodesic march per pixel is unaffordable mid-dive);
// this stretches it onto the full drawable. Deliberately dumb — bilinear soft.
fragment float4 blit_fragment(LensVSOut in [[stage_in]],
                              texture2d<float> src [[texture(0)]]) {
    constexpr sampler smp(address::clamp_to_edge, filter::linear);
    return src.sample(smp, in.uv);
}
