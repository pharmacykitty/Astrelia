import SwiftUI
import simd

// The black-hole dive easter egg (design of record: docs/black-hole-dive.md).
// Free-flying into Sagittarius A*'s event horizon hands the camera to this
// timeline: a staged plunge modelled on NASA's "Beyond the Brink" visualization
// (approach → 99% c → horizon crossing → interior → spaghettification → white-out),
// rendered by the in-map lensing pass — one continuous shot, no cutscene. Swift
// sequences the beats by pushing `DiveStage` uniforms; progress is time-anchored
// so render stalls can't speed the fall.

enum DiveTimeline {
    static let duration: TimeInterval = 30
    /// Progress at which the horizon is crossed (the aperture collapse begins).
    static let crossing = 0.60
    /// NASA's number for Sgr A*: seconds from horizon to singularity.
    static let secondsToSingularity = 12.8
    /// Real Schwarzschild radius of Sgr A* (~4.3 M solar masses), in km.
    static let realRsKm = 1.27e7

    private static func ramp(_ p: Double, _ a: Double, _ b: Double) -> Float {
        let t = max(0, min(1, (p - a) / max(1e-6, b - a)))
        return Float(t * t * (3 - 2 * t))   // smoothstep
    }

    /// Infall speed as a fraction of c — the storytelling curve (NASA's stages:
    /// 19% on approach, 41–76% midway, 99.2% at the horizon).
    static func beta(at p: Double) -> Double {
        let b = 0.19 + 0.36 * Double(ramp(p, 0, 0.20))          // approach → 0.55
              + 0.35 * Double(ramp(p, 0.20, 0.50))              // plunge → 0.90
              + 0.092 * Double(ramp(p, 0.50, 0.62))             // critical → 0.992
        return min(b, 0.992)
    }

    /// The camera's render distance in stylised rs units: a genuine fall — the
    /// shadow grows the whole way in — floored at ~7 rs, where (in portrait) the
    /// shadow spans the screen and only inverse aberration holds it at bay.
    static func holdDistanceRs(at p: Double, from startRs: Float) -> Float {
        let toArc = ramp(p, 0, 0.15)
        let approach = ramp(p, 0.05, 0.92)
        let arc: Float = 11.5 - 5.1 * approach                  // 11.5 → 6.4 rs
        return startRs + (arc - startRs) * toArc
    }

    /// The infalling observer sees the outside universe fast-forward: the disc's
    /// orbital swirl runs up to ~5× near the horizon.
    static func timeWarp(at p: Double) -> Double {
        1 + 4 * Double(ramp(p, 0.25, 0.62))
    }

    /// Slow, accelerating camera roll — the vertigo of the spiral fall.
    static func rollAngle(at p: Double) -> Float {
        0.65 * ramp(p, 0.12, 0.92)
    }

    /// Mid-plunge field-of-view widening: the speed-rush cue. Modest — widening
    /// shrinks the hole on screen, and engulfment matters more than the zoom.
    static func fovBoost(at p: Double) -> Float {
        1 + 0.12 * ramp(p, 0.25, 0.65)
    }

    /// Shader uniforms for this instant. `reduceMotion` softens the violent warps
    /// (aberration squeeze, tidal stretch) without shortening the story.
    static func stage(at p: Double, reduceMotion: Bool) -> DiveStage {
        var s = DiveStage()
        let motion: Float = reduceMotion ? 0.45 : 1.0
        s.beta = Float(beta(at: p)) * motion
        s.bakeMix = ramp(p, 0.15, 0.45)                          // whole-sky bake before heavy aberration
        // Steady flare through the plunge + a photon-ring blaze right at the crossing.
        s.discBoost = 0.4 * ramp(p, 0.2, 0.55) * (1 - ramp(p, 0.85, 0.97))
                    + 1.1 * (ramp(p, 0.56, 0.62) - ramp(p, 0.65, 0.72))
        s.aperture = ramp(p, crossing, crossing + 0.12)          // the universe closes behind
        s.spaghetti = ramp(p, 0.66, 0.92) * motion
        // Reaches 1.0 just before the flash: the last light dies completely — the
        // white-out rises from true black.
        s.redshift = 0.25 * ramp(p, 0.5, 0.62) + 0.75 * ramp(p, 0.66, 0.95)
        s.flash = ramp(p, 0.965, 0.995)
        return s
    }

    // MARK: HUD narration

    struct HUD {
        var headline: String
        var lines: [String]
    }

    static func hud(at p: Double) -> HUD {
        let b = beta(at: p)
        let gamma = 1 / (1 - b * b).squareRoot()
        let speedPct = Int((b * 100).rounded())
        if p < crossing {
            // Distance narration: map progress to the *real* infall NASA describes
            // (millions of km), so the numbers are honest even though the map's
            // hole is stylised. From ~110M km down to the horizon.
            let km = max(0, 110.0 * pow(1 - p / crossing, 1.6))
            let dist = km > 1 ? String(format: "%.0f million km above the horizon", km)
                              : "At the event horizon"
            return HUD(headline: "Falling toward Sagittarius A*",
                       lines: ["\(speedPct)% of light speed",
                               dist,
                               String(format: "Time runs %.1f× slower for you", gamma)])
        } else if p < 0.97 {
            let remaining = max(0, secondsToSingularity * (1 - (p - crossing) / (0.97 - crossing)))
            return HUD(headline: "Inside the event horizon",
                       lines: ["Every path now leads inward",
                               String(format: "Singularity in %.1f s", remaining),
                               "Tidal gravity is stretching you"])
        } else {
            return HUD(headline: " ", lines: [])
        }
    }
}

/// The translucent narration card shown during the dive — the app's
/// "numbers → intuition" voice, kept quiet and factual while the sky warps.
struct DiveHUD: View {
    let progress: Double
    let onSkip: () -> Void

    var body: some View {
        let hud = DiveTimeline.hud(at: progress)
        VStack(spacing: 10) {
            Spacer()
            if !hud.lines.isEmpty {
                VStack(spacing: 5) {
                    Text(hud.headline)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                    ForEach(hud.lines, id: \.self) { line in
                        Text(line)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(0.65))
                            .monospacedDigit()
                    }
                }
                .padding(.vertical, 12).padding(.horizontal, 18)
                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .transition(.opacity)
            }
            Button(action: onSkip) {
                Text("Skip")
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.vertical, 6).padding(.horizontal, 14)
                    .background(.black.opacity(0.3), in: Capsule())
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(true)
        .animation(.easeInOut(duration: 0.4), value: hud.headline)
    }
}

/// The post-dive caption: honest physics, gentle exit. Anchored near the top so
/// it never overlaps the Sgr A* selection card at the bottom.
struct DiveEpilogue: View {
    var body: some View {
        VStack {
            Text("You crossed the event horizon of Sagittarius A*.\nNothing that enters ever leaves — the simulation has been rewound.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.vertical, 12).padding(.horizontal, 18)
                .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.top, 140)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}
