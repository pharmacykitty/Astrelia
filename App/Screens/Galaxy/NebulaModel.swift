import Foundation
import simd
import Synchronization

/// A baked particle cloud for a deep-sky landmark — the positions + colours produced
/// offline by `tools/nebula_bake.py` from a public-domain photo, so the object renders
/// in its true shape using our additive sprites. Coordinates are normalised to
/// [-1, 1] (y up); the renderer places the sheet facing Earth and synthesises depth.
struct NebulaParticleSet: Sendable {
    let gas: [(pos: SIMD2<Float>, color: SIMD3<Float>)]
    let dust: [SIMD2<Float>]
}

/// Loads + caches bundled `.nbl` datasets. Returns nil (→ procedural fallback) if a
/// landmark has no bake or the file is missing/corrupt.
enum NebulaLibrary {
    /// landmark.id → bundled resource name (the `.nbl` under App/Resources/Nebulae).
    /// Each is baked offline from a public-domain / CC BY 4.0 visible-light photo
    /// (see `tools/nebula_bake.py` and the Sources screen). Landmarks without a bake
    /// fall back to the procedural sprite shapes.
    static let baked: [String: String] = [
        "m42": "m42",            // Orion Nebula
        "m16": "m16",            // Eagle Nebula (Pillars of Creation)
        "m8": "m8",              // Lagoon Nebula
        "m20": "m20",            // Trifid Nebula
        "carina": "carina",      // Carina Nebula
        "tarantula": "tarantula",// Tarantula Nebula
        "m1": "m1",              // Crab Nebula
        "veil": "veil",          // Veil Nebula
        "m57": "m57",            // Ring Nebula
        "helix": "helix",        // Helix Nebula
        "cone": "cone",          // Cone Nebula
        "naamerica": "naamerica",// North America Nebula
        "bubble": "bubble",      // Bubble Nebula
        "m17": "m17",            // Omega / Swan Nebula
        "lobster": "lobster",    // Lobster / War & Peace Nebula
        "horsehead": "horsehead",// Horsehead Nebula
        "m27": "m27",            // Dumbbell Nebula
        "m76": "m76",            // Little Dumbbell Nebula
        "southernring": "southernring", // Southern Ring Nebula
        "bug": "bug",            // Butterfly / Bug Nebula
        "saturn": "saturn",      // Saturn Nebula
        "eskimo": "eskimo",      // Eskimo Nebula
        "vela": "vela",          // Vela Supernova Remnant
        "jellyfish": "jellyfish",// Jellyfish Nebula (IC 443)
        "pacman": "pacman",      // Pacman Nebula
        "rosette": "rosette",    // Rosette Nebula
        "california": "california", // California Nebula
    ]

    /// Parsed datasets, kept for the app's lifetime (~25 MB when all 27 are loaded)
    /// so scene rebuilds never re-read or re-parse the bundle. Failed loads cache
    /// `nil` too, so a missing/corrupt file isn't re-attempted. A `Mutex` rather
    /// than `@MainActor` so scene builders can run off the main actor.
    private static let cache = Mutex<[String: NebulaParticleSet?]>([:])

    static func model(for landmarkID: String) -> NebulaParticleSet? {
        guard let name = baked[landmarkID] else { return nil }
        return cache.withLock { cache in
            if let cached = cache[name] { return cached }
            let parsed = load(name)
            cache[name] = .some(parsed)
            return parsed
        }
    }

    private static func load(_ name: String) -> NebulaParticleSet? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "nbl"),
              let data = try? Data(contentsOf: url), data.count >= 12 else { return nil }
        return data.withUnsafeBytes { raw -> NebulaParticleSet? in
            guard raw[0] == 0x4E, raw[1] == 0x42, raw[2] == 0x4C, raw[3] == 0x32 else { return nil }  // 'NBL2'
            let base = raw.baseAddress!
            func u32(_ o: Int) -> Int { Int(base.loadUnaligned(fromByteOffset: o, as: UInt32.self)) }
            func f32(_ o: Int) -> Float { base.loadUnaligned(fromByteOffset: o, as: Float.self) }
            let gasCount = u32(4), dustCount = u32(8)
            guard data.count >= 12 + gasCount * 20 + dustCount * 8 else { return nil }
            var o = 12
            var gas: [(pos: SIMD2<Float>, color: SIMD3<Float>)] = []
            gas.reserveCapacity(gasCount)
            for _ in 0..<gasCount {
                gas.append((SIMD2(f32(o), f32(o + 4)), SIMD3(f32(o + 8), f32(o + 12), f32(o + 16))))
                o += 20
            }
            var dust: [SIMD2<Float>] = []
            dust.reserveCapacity(dustCount)
            for _ in 0..<dustCount {
                dust.append(SIMD2(f32(o), f32(o + 4)))
                o += 8
            }
            return NebulaParticleSet(gas: gas, dust: dust)
        }
    }
}
