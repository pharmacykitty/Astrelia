import SwiftUI
import simd

// The black-hole dive easter egg (design of record: docs/black-hole-dive.md).
//
// Not a scripted cutscene: free-flying inside the point of no return (~6 rs)
// hands your ACTUAL position and velocity to a gravitational free-fall the
// renderer integrates per display-link frame. Every relativistic effect is a
// function of where you are — β = √(rs/r) (the real free-fall law), the shadow
// genuinely swallowing the sky as r → rs, the horizon blackout the raymarcher
// produces naturally — per NASA's "Beyond the Brink". Inside the horizon the
// render radius holds just outside (all light terminates when the camera is
// truly inside; there would be nothing to show) while the narrative radius runs
// down Sgr A*'s real ~12.8 s proper time to the singularity: the last light
// reddens, stretches, and dies, then the flash — and the rewind.

/// Imperative side-channel between the fly loop, the renderer, and the HUD.
/// The dive must not depend on a SwiftUI render to start or advance: under
/// 60 Hz flight churn SwiftUI's update graph can wedge (observed on simulator),
/// while the display link keeps running.
@MainActor
final class DiveChannel {
    var start: Date?
    var entryEye = SIMD3<Float>(0, 0, 0)
    var entryVelocity = SIMD3<Float>(0, 0, 0)   // pc/s at handoff
    var entryForward = SIMD3<Float>(0, 0, -1)
    var reduceMotion = false
    var currentRRs: Double = .infinity          // renderer → HUD (narrative radius, rs)
    var finished = false                        // renderer → fly loop (time to rewind)
}

enum DivePhysics {
    /// The point of no return: free flight crossing this radius belongs to gravity.
    static let captureRadiusRs: Float = 6
    /// The narrative singularity: the flash peaks here and the rewind follows.
    static let endRadiusRs: Float = 0.15
    /// Visualization floor for the camera pose: inside ~4.5 rs the whole forward
    /// view lies within the shadow (the escape cone points backward) — physically
    /// true, but a black screen. The pose holds here while the narrative radius
    /// keeps falling and the effects (β, flare, redshift) tell the crossing.
    static let renderFloorRs: Float = 4.5
    /// NASA's number for Sgr A*: proper seconds from horizon to singularity.
    static let secondsToSingularity = 12.8
    /// Real Schwarzschild radius of Sgr A* (~4.3 M solar masses), in km.
    static let realRsKm = 1.27e7
    /// Newtonian-styled pull (rs³/s², stylised), tuned so the fall from 6 rs to
    /// the horizon takes ~9 s even from rest.
    static let gravity: Float = 3.1
    /// Constant narrative descent inside the horizon: 1 rs → end in exactly 12.8 s.
    static var interiorRateRsPerS: Float { (1 - endRadiusRs) / Float(secondsToSingularity) }
    /// A hot approach shouldn't skip the show: entry speed is clamped (rs/s).
    static let maxEntrySpeedRsPerS: Float = 1.6
    static let maxFallSpeedRsPerS: Float = 3.4
    /// Belt-and-braces: if integration ever stalls, the fly loop force-ends the dive.
    static let failsafeSeconds: TimeInterval = 90

    private static func clamp01(_ x: Double) -> Double { max(0, min(1, x)) }

    /// Free-fall speed from rest at infinity — the real law: β = √(rs/r).
    static func beta(atRs r: Double) -> Double {
        min(0.995, (1 / max(r, 1.0001)).squareRoot())
    }

    /// The infalling observer sees the outside universe fast-forward with speed.
    static func timeWarp(atRs r: Double) -> Double {
        1 + 4 * pow(beta(atRs: max(r, 1)), 2)
    }

    /// Shader staging as a pure function of the narrative radius. `reduceMotion`
    /// softens the violent warps without changing the story.
    static func stage(atRs r: Double, reduceMotion: Bool) -> DiveStage {
        var s = DiveStage()
        let motion: Float = reduceMotion ? 0.45 : 1
        s.beta = Float(beta(atRs: max(r, 1))) * motion       // β holds its horizon value inside
        s.bakeMix = Float(clamp01((14 - r) / 6))             // whole-sky bake well before the plunge deepens
        // Disc flares with proximity, blazing right at the horizon (photon pile-up).
        let flare = exp(-pow((r - 1.05) / 0.3, 2))
        s.discBoost = Float(0.35 * clamp01((10 - r) / 6) + 1.1 * flare)
        // Inside: the last light reddens, stretches, and dies on the way down.
        let inside = clamp01((1 - r) / Double(1 - endRadiusRs))
        s.redshift = Float(pow(inside, 0.8))
        s.spaghetti = Float(clamp01((inside - 0.15) / 0.6)) * motion
        s.flash = Float(clamp01((Double(endRadiusRs) + 0.09 - r) / 0.09))
        return s
    }

    // MARK: HUD narration — honest numbers from the actual radius

    struct HUD {
        var headline: String
        var lines: [String]
    }

    static func hud(atRs r: Double) -> HUD {
        if r > 1 {
            let b = beta(atRs: r)
            let km = (r - 1) * realRsKm / 1e6
            let gamma = 1 / max(0.02, (1 - 1 / max(r, 1.02)).squareRoot())
            return HUD(headline: "Falling toward Sagittarius A*",
                       lines: ["\(Int((b * 100).rounded()))% of light speed",
                               km >= 1 ? String(format: "%.0f million km above the horizon", km)
                                       : "At the event horizon",
                               String(format: "Time runs %.1f× slower for you", gamma)])
        } else if r > Double(endRadiusRs) + 0.02 {
            let remaining = (r - Double(endRadiusRs)) / Double(interiorRateRsPerS)
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
    let rRs: Double
    let onSkip: () -> Void

    var body: some View {
        let hud = DivePhysics.hud(atRs: rRs)
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
