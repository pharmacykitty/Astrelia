#include <metal_stdlib>
using namespace metal;

// One instanced, billboarded soft-sprite pipeline renders almost the entire Galaxy
// Map: stars, the Milky Way point field, nebula gas, cluster members, glows. Each
// layer is just a list of these instances with a blend mode. Positions are in world
// space (parsecs, Sun at origin); the vertex stage works camera-relative for float
// precision over the galaxy's huge scale range.

struct SpriteInstance {
    // Kept as a flat run of 12 floats so Swift's memory layout matches exactly with
    // no float3 alignment surprises.
    float px, py, pz;        // world position (parsecs)
    float radius;            // world radius (mode 0) OR screen coefficient (mode 1)
    float r, g, b, a;        // colour + opacity
    float minPixel, maxPixel;// size clamp (points)
    float softness;          // 0 = hard disc (stars), 1 = soft glow (gas/bloom)
    float mode;              // 0 = world-sized (×focal/depth), 1 = screen-sized (÷depth)
};

struct Uniforms {
    float4x4 viewProj;       // camera-relative (eye at origin) view-projection
    float ex, ey, ez;        // world camera position (subtracted → camera-relative)
    float halfHeightFocal;   // (viewportHeight/2) · focal, in points
    float viewW, viewH;      // viewport, in points
    float logDepthC;         // logarithmic-depth constant (precision over huge range)
    float pad0;
};

struct VSOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float softness;
};

constant float2 kCorners[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };

vertex VSOut sprite_vertex(uint vid [[vertex_id]],
                           uint iid [[instance_id]],
                           const device SpriteInstance* inst [[buffer(0)]],
                           constant Uniforms& u [[buffer(1)]]) {
    SpriteInstance s = inst[iid];
    VSOut out;
    out.color = float4(s.r, s.g, s.b, s.a);
    out.softness = s.softness;
    out.uv = kCorners[vid];

    float3 rel = float3(s.px, s.py, s.pz) - float3(u.ex, u.ey, u.ez);
    float4 clip = u.viewProj * float4(rel, 1.0);
    if (clip.w <= 0.0001) {            // behind camera → push outside the frustum
        out.position = float4(2.0, 2.0, 2.0, 1.0);
        return out;
    }

    // Apparent size in points, then converted to an NDC offset (×w to survive the
    // perspective divide). mode 0 scales with distance (world-sized), mode 1 is the
    // screen heuristic the Canvas renderer used (coefficient ÷ depth, clamped).
    float worldPx = s.radius * u.halfHeightFocal / clip.w;
    float screenPx = s.radius / clip.w;
    float px = clamp(s.mode < 0.5 ? worldPx : screenPx, s.minPixel, s.maxPixel);
    float2 ndc = kCorners[vid] * (px / (float2(u.viewW, u.viewH) * 0.5)) * clip.w;

    out.position = clip;
    out.position.xy += ndc;

    // Logarithmic depth: high precision near the camera, monotonic out to the galaxy
    // edge. (Sprites blend additively with depth test off, but a valid depth keeps
    // the buffer usable for any future opaque geometry.)
    out.position.z = log2(max(1e-6, u.logDepthC * clip.w + 1.0)) /
                     log2(u.logDepthC * 200000.0 + 1.0) * clip.w;
    return out;
}

// Additive sprites return premultiplied colour (blend ONE, ONE): light accumulates.
fragment float4 sprite_additive(VSOut in [[stage_in]]) {
    float r = length(in.uv);
    float exponent = mix(0.25, 2.2, in.softness);   // hard disc → soft glow
    float mask = pow(saturate(1.0 - r), exponent);
    float a = in.color.a * mask;
    return float4(in.color.rgb * a, a);
}

// Depth-only occluder: invisible caps marking a landmark's dense, opaque core. They
// write the rasteriser depth (shared sprite_vertex → values consistent with the light
// sprites that test against them) but emit no light, so background stars behind a dense
// nebula/galaxy/cluster are culled. The soft outer ring is discarded so only the solid
// centre writes depth (and the union of many caps traces the bright shape).
fragment float4 sprite_occluder(VSOut in [[stage_in]]) {
    float r = length(in.uv);
    if (r > 0.9) discard_fragment();
    return float4(0.0);
}

// Normal-blend sprites (dust, event horizons) return straight colour and use
// srcAlpha / 1-srcAlpha to *subtract* light from the additive result beneath.
fragment float4 sprite_overlay(VSOut in [[stage_in]]) {
    float r = length(in.uv);
    float mask = saturate(1.0 - r);
    return float4(in.color.rgb, in.color.a * mask);
}
