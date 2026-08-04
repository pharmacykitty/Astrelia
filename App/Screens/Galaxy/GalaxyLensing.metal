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
                      float time, float3 photonDir, float boost, float beamCap) {
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

    float radial = pow(rIn / rd, 2.2);                     // emissivity falls off outward
    // beamCap: the interior ramps this down (2.2 → ~1.15). Rays winding near the
    // photon sphere cross the disc dozens of times, EACH at maximum beaming —
    // uncapped, the magnified interior view accumulates luminance in the
    // hundreds and floods flat white; no downstream tonemap can save that.
    float dopC = clamp(dop, 0.25, beamCap);
    float beam = pow(dopC, 3.0);                           // beaming: white earns the centre only
    float3 shifted = col;
    shifted = mix(shifted * float3(1.0, 0.42, 0.22), shifted, saturate(dopC));               // receding limb reddens + dims
    shifted = mix(shifted, shifted * float3(1.16, 1.05, 0.90) + 0.20, saturate(dopC - 1.0)); // approaching limb whitens (warm, not blue)
    // NASA SVS 14585 palette check (frame-by-frame, 2026-07-31): their frames are
    // near-black with SATURATED red-orange fire in thin streams — white almost
    // nowhere. Gain down (1.6 → 1.05) and saturation up (1.3 → 1.45): the fire
    // stays fire, and the photon ring reads as the thin bright line it should be.
    float3 rgb = shifted * (radial * texture * beam) * grav * 1.05 * (1.0 + boost * 2.0);
    float dlum = dot(rgb, float3(0.30, 0.55, 0.15));
    rgb = max(float3(0.0), mix(float3(dlum), rgb, 1.45));  // saturation push toward the fire

    // Optically THICK (NASA's disc shows a single surface, not stacked layers):
    // high alpha kills the transmittance after the first crossing or two, so the
    // fire keeps its swirl texture instead of layering into white.
    float alpha = saturate((0.10 + 0.90 * smoothstep(0.40, 1.15, texture)) * (1.0 - t * 0.92) * 1.4);
    return float4(rgb, alpha);
}

// NASA-fire tonemap for the disc's accumulated HDR light (SVS 14585): brightness
// climbs a blackbody-style ramp — black → deep red → vivid orange → amber — and
// earns WHITE only at photon-ring luminance. The old channel-wise knee scaled
// R,G,B together, so stacked lensed crossings clipped into pale cream sheets;
// mapping the luminance through a fire ramp keeps every bright pixel saturated.
// A trace of the pixel's own hue survives (Doppler limb asymmetry stays visible).
static float3 bh_fireTone(float3 rgb) {
    float lum = dot(rgb, float3(0.30, 0.55, 0.15));
    if (lum < 1e-5) return rgb;
    float L = lum / (4.0 + lum);                           // filmic-ish; white needs lum ≳ 23
    float3 ramp;
    if (L < 0.35)      ramp = mix(float3(0.0),               float3(0.62, 0.07, 0.01), L / 0.35);
    else if (L < 0.62) ramp = mix(float3(0.62, 0.07, 0.01),  float3(1.00, 0.42, 0.05), (L - 0.35) / 0.27);
    else if (L < 0.85) ramp = mix(float3(1.00, 0.42, 0.05),  float3(1.02, 0.62, 0.22), (L - 0.62) / 0.23);
    else               ramp = mix(float3(1.02, 0.62, 0.22),  float3(1.28, 1.20, 1.08), saturate((L - 0.85) / 0.15));
    float3 hue = saturate(rgb / max(lum, 1e-5));
    return ramp * mix(float3(1.0), hue, 0.30);
}

// Post effects shared by every pixel (dive staging). Disc light arrives already
// fire-tonemapped (LDR); the headlight boost here applies to the BACKGROUND only
// — the disc's own boost is folded in before its tonemap (bh_fireTone input).
static float4 bh_post(float3 col, float a, float3 screenDir, float3 fwd, constant LensUniforms& u) {
    if (u.redshiftG > 0.001) {                             // the interior death, centre-first
        // Hamilton (JILA): deep inside, the fore/aft view redshifts and dies
        // FIRST while the sideways sky stays bright and blueshifted — the outside
        // universe's last light is a ring around your waist, not a uniform fade.
        // Screen mapping: the frame centre (the illusory horizon ahead) embers
        // and dies early; the tunnel walls at the frame edge survive longest,
        // slightly cooled. Contrast-deepening ember (pow > 1 on luminance): dim
        // light goes to black, bright filaments stay saturated — a flat linear
        // blend turned the whole interior into one copper wall.
        float axial = saturate(dot(screenDir, fwd));
        axial *= axial;                                    // 1 at centre → 0 at the edge
        float rG = u.redshiftG * mix(0.55, 1.0, axial);
        float lum = dot(col, float3(0.30, 0.55, 0.15));
        float3 ember = pow(max(lum, 0.0), 1.6) * float3(1.15, 0.44, 0.18);
        col = mix(col, ember, rG * 0.8);
        col *= 1.0 - rG * rG * 0.96;
        col = mix(col, col * float3(0.88, 0.96, 1.14), u.redshiftG * (1.0 - axial) * 0.5);
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

    // Tidal spaghettification: stretch the image radially along the fall axis.
    // Capped at ~2.3× — the old 6× magnified the reduced-res target into giant
    // posterized smears (the "broken" interior frames).
    if (u.spaghetti > 0.001) {
        float4 hc = u.viewProj * float4(hp, 1.0);
        float2 hndc = hc.w > 0.001 ? hc.xy / hc.w : float2(0.0);
        float2 dv = ndc - hndc;
        float stretch = 1.0 + u.spaghetti * 1.3 * exp(-length(dv) * 1.6);
        ndc = hndc + dv / stretch;
    }

    float3 screenDir = normalize(fwd + right * (ndc.x * u.tanHalfW) + up * (ndc.y * u.tanHalfH));
    float3 dir = screenDir;
    // Relativistic aberration, INVERSE map: negative β crowds the sky into view
    // (approach compression); positive warp MAGNIFIES the forward view. The
    // aperture rides the warp positive through the interior: the view plunges
    // INTO the darkness — the black centre swallowing outward while the disc and
    // lensed sky stream past the frame edges. (Compression toward the centre
    // reads as receding — that's the failed "collapse dome" — magnification
    // toward the axis is the falling-in cue.)
    float warp = clamp(-0.6 * u.beta + 1.45 * u.aperture, -0.95, 0.9);
    if (fabs(warp) > 0.001) dir = bh_aberrate(dir, fwd, warp);

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
                    float beamCap = mix(2.2, 1.15, saturate(u.aperture * 1.3));
                    float4 d = bh_disc(xp, n, rd, rIn, rOut, u.time, normalize(v), u.discBoost, beamCap);
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
            float2 m = min(suv, 1.0 - suv);
            screenW = saturate(min(m.x, m.y) / 0.015);
            if (screenW > 0.0) {
                float4 s = sceneTex.sample(smp, suv);
                bg = s.rgb; bgA = s.a;
            }
        }
        // Only rays the hole actually BENT may fall back to the baked panorama —
        // an unbent edge pixel must keep its own screen sample, or the bake's warm
        // wash paints a border around the whole frame wherever the lens is active.
        float bent = saturate((1.0 - dot(outDir, dir)) * 400.0);
        float bakeW = max((1.0 - screenW) * bent, u.bakeMix);
        if (bakeW > 0.001) {
            // Wrap longitude so rays crossing the panorama's ±π seam stay continuous.
            // Mip-filtered: auto derivatives pick the right level whether the warp
            // magnifies (interior tunnel) or minifies (approach compression) the
            // panorama — without mips the star sprites alias into blue confetti
            // sheets mid-dive. The aperture bias adds a deliberate extra blur as
            // the interior magnification grows.
            constexpr sampler wrapSmp(s_address::repeat, t_address::clamp_to_edge,
                                      filter::linear, mip_filter::linear);
            float2 buv = bh_equirect(outDir);
            // ANALYTIC mip level — never derivative-based: in the march zone
            // neighbouring rays diverge chaotically, so auto-lod flips per pixel
            // and sprays coloured grain. Two smooth terms instead: the dive state
            // (magnified stars soften into round dots) and the bend amount
            // (strongly-lensed sectors compress many images — blur matches that).
            float dlod = saturate(max(u.aperture * 1.4, (u.beta - 0.15) * 1.3)) * 2.2;
            float blod = saturate((1.0 - dot(outDir, dir)) * 3.0) * 2.5;
            float lodF = clamp(dlod + blod, 0.0, 6.0);
            float4 b = skyTex.sample(wrapSmp, buv, level(lodF));
            // Council fix (2026-08-04): the dive's hard bake dim deleted the
            // UNIVERSE along with the glow — and falling is only legible as the
            // loss of a referent. Unsharp-split the bake: a coarse mip is the
            // warm glow (still dies with speed, below); fine-minus-coarse is the
            // POINT STARS, re-added after the dims so the sky stays populated —
            // streaming past on approach, surviving longest at the frame edge
            // inside (Hamilton's sideways sky), guttering out before the flash.
            float diveAmt = saturate(max(u.beta * 1.8, u.aperture * 2.0));
            float3 bStars = float3(0.0);
            if (diveAmt > 0.001) {
                float lodStar = clamp(max(lodF * 0.6, 1.0), 1.0, 2.5);   // soft dots, never confetti
                float3 coarse = skyTex.sample(wrapSmp, buv, level(lodStar + 3.0)).rgb;
                bStars = max(skyTex.sample(wrapSmp, buv, level(lodStar)).rgb - coarse, 0.0);
                // Compact bright bake patches (nebulae, the nucleus) survive the
                // unsharp split as big "stars" and gain into pale smears. Real
                // point stars sit on a DARK neighbourhood (coarse ≈ 0); suppress
                // the detail wherever the neighbourhood itself is bright, and cap
                // the per-pixel luminance for whatever slips through.
                bStars *= saturate(1.0 - dot(coarse, float3(0.30, 0.55, 0.15)) * 5.0);
                float slum0 = dot(bStars, float3(0.30, 0.55, 0.15));
                bStars *= min(1.0, 0.30 / max(slum0, 1e-4));
            }
            // The bake resolves individual stars but under-samples the soft bulge
            // wash (its sprites shrink to true angular size); add the nucleus glow
            // procedurally — a warm band hugging the galactic plane — so strongly
            // bent rays blend seamlessly with the on-screen haze.
            float3 n = normalize(float3(u.dnx, u.dny, u.dnz));
            float planeDist = dot(outDir, n);
            // The Milky Way as a THIN, dusty, textured band (NASA SVS 14585): the
            // luminous actor that lensing bends into arcs and rings around the
            // shadow — not a warm fog. Persists through the plunge (it's the show);
            // only a faint wide haze fades with speed and proximity.
            // Thin + dim (NASA: the band is a dusty grey-white ribbon on BLACK sky,
            // not a cream flood — at 0.32 the wash filled whole dive frames).
            float bandProfile = exp(-planeDist * planeDist * 55.0);
            float bandTex = 0.55 + 0.45 * bh_noise(float2(atan2(outDir.y, outDir.x) * 6.0,
                                                          planeDist * 14.0));
            b.rgb += float3(0.66, 0.58, 0.48) * (0.12 * bandProfile * bandTex);
            float haze = exp(-planeDist * planeDist * 5.0) * 0.05
                       * (1.0 - 0.8 * saturate(u.beta / 0.7))
                       * saturate((length(hp) / u.rs - 5.0) / 15.0);
            b.rgb += float3(1.0, 0.82, 0.55) * haze;
            // Dive tone knee on the bake: the map's warm nucleus glow lenses into
            // big cream sheets mid-plunge (NASA's sky is a star band on black).
            // Compress the bake's highlights as speed builds; parked views keep
            // the map's own warm look untouched.
            float bknee = saturate(u.beta * 1.8);
            if (bknee > 0.001) {
                float blum = dot(b.rgb, float3(0.30, 0.55, 0.15));
                b.rgb = mix(b.rgb, b.rgb / (1.0 + 1.4 * blum), bknee);
                // NASA's sky is near-BLACK with a thin star ribbon: the knee alone
                // left the magnified bulge glow as pale sheets — dim the whole bake
                // hard as speed builds (parked views untouched, bknee = 0).
                b.rgb *= 1.0 - 0.72 * bknee;
            }
            if (diveAmt > 0.001) {
                // The surviving sky. Approach: stars everywhere, streaming.
                // Interior: survival migrates to the frame edge (the sideways sky
                // outlives fore/aft), the dots redden as they die, and the whole
                // population gutters out across r ~0.5 → 0.2 so the LAST star
                // dies just before the flash — its extinction is the countdown.
                // Survival is SCREEN-space: dot(screenDir, fwd) only spans
                // ~0.82–1.0 across a phone FOV, which crushed every star to ~0.
                // The NDC radius is the honest "how far from the death at the
                // centre" measure — edges keep their stars, the centre loses
                // them first, and everything gutters out together via `life`.
                float edge = saturate(length(ndc));
                float inside = saturate(u.aperture * 1.35);
                float surv = mix(1.0, clamp(edge, 0.12, 1.0), inside);
                float life = 1.0 - smoothstep(0.60, 0.93, u.aperture);
                float slum = dot(bStars, float3(0.30, 0.55, 0.15));
                float3 starCol = mix(bStars, slum * float3(1.0, 0.45, 0.22), inside * 0.7);
                b.rgb += starCol * (2.4 + 0.8 * inside) * surv * life;
                b.a = max(b.a, saturate(slum * 1.5) * surv * life * 0.6);
            }
            b.a = max(b.a, bandProfile * 0.5);
            bg = mix(bg, b.rgb, bakeW);
            bgA = mix(bgA, b.a, bakeW);
        }
        // Surviving outside light dims gently as the plunge deepens (the tunnel's
        // magnification already thins it; the redshift ramp does the killing).
        // Chroma washes slightly warm at high warp so magnified equirect texels
        // can't rainbow-band.
        if (u.aperture > 0.001) {
            float lum = dot(bg, float3(0.30, 0.55, 0.15));
            // Mild warm wash only — the mip-filtered bake no longer rainbow-bands,
            // and a strong wash flattened the whole interior into one copper tone.
            bg = mix(bg, lum * float3(1.0, 0.93, 0.80), saturate(u.aperture * u.aperture * 0.3));
            bg *= 1.0 - 0.55 * u.aperture;
            bgA *= 1.0 - 0.4 * u.aperture;
        }
    }

    // Doppler headlight: the forward boost is folded into the disc's HDR light
    // BEFORE its fire tonemap (so beaming brightens the fire along the ramp
    // instead of re-clipping tonemapped values to cream); the background gets it
    // in LDR with its own soft knee. The disc skips the blue tint — NASA's fire
    // stays warm at every speed.
    float ahead = saturate(dot(dir, fwd));
    float head = u.beta > 0.001 ? 1.0 + u.beta * 1.1 * ahead * ahead * ahead : 1.0;
    // The disc takes the headlight at half strength — mid-plunge every warped
    // ray is near-forward, and the full boost just doubled the stacked images.
    // PARKED, the disc keeps its raw HDR light (clipping at the target = the
    // approved crisp orange disc + white-hot ring identity); the NASA-fire
    // tonemap takes over as the dive builds speed — that's when stacked lensed
    // images would otherwise flood the frame cream.
    float3 fire = bh_fireTone(acc * (1.0 + (head - 1.0) * 0.55));
    float3 discCol = mix(acc, fire, saturate(u.beta * 1.6));
    float3 bgCol = bg * head * mix(float3(1.0), float3(0.86, 0.94, 1.18), u.beta * ahead * 0.6);
    float bglum = dot(bgCol, float3(0.30, 0.55, 0.15));
    bgCol = mix(bgCol, bgCol / (1.0 + 0.6 * bglum), saturate(u.beta * 1.5));

    float3 col = discCol + bgCol * trans;
    // The shadow must be a solid black ball (not the UI gradient leaking through);
    // the disc adds its own coverage on top of whatever background survives.
    float a = captured ? 1.0 : max(bgA * trans, saturate(1.0 - trans));

    // bh_post gets the SCREEN ray (pre-aberration): the interior's centre-vs-edge
    // weighting is compositional — post-warp directions all crowd toward fwd.
    float4 res = bh_post(col, a, screenDir, fwd, u);
    // Ember floor (council, 2026-08-04): where the ray carries fire, the interior
    // never drops below ~3% luminance — on a real phone true black reads as a
    // frozen app, not drama. Only the flash extinguishes the embers.
    if (u.aperture > 0.2) {
        float discSig = saturate(1.0 - trans);
        res.rgb = max(res.rgb, float3(0.034, 0.011, 0.004) * (discSig * (1.0 - u.flash)));
        res.a = max(res.a, 0.9 * discSig);
    }
    // Blue-noise-ish dither: the interior's long smooth ramps posterize on the
    // 8-bit reduced-res target without it.
    res.rgb += (bh_hash(in.uv * float2(u.viewW, u.viewH) + fract(u.time * 0.37) * 61.0) - 0.5)
               * (2.0 / 255.0);
    return res;
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
// texture (a native-res geodesic march per pixel is unaffordable mid-dive);
// this stretches it onto the full drawable. Deliberately dumb — bilinear soft.
fragment float4 blit_fragment(LensVSOut in [[stage_in]],
                              texture2d<float> src [[texture(0)]]) {
    constexpr sampler smp(address::clamp_to_edge, filter::linear);
    return src.sample(smp, in.uv);
}
