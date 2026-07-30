import Foundation

/// A tiny deterministic LCG so seeded procedural art (galaxy landmarks, baked
/// nebula depth, starfields) is stable across redraws and runs.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
