import Foundation
import CelestialCore

/// Loads the bundled HYG star catalog (mag ≤ 7.5, ~25k distance-known stars) once,
/// off the main thread, and hands it to the UI. The sky view filters this down by
/// magnitude; the Galaxy Map uses the full set for 3D depth.
///
/// Backed by a packed binary (`stars.bin`, memory-mapped) rather than CSV, so it
/// loads in a few ms and scales to a far larger catalog without slowing launch.
@MainActor
@Observable
final class StarCatalogStore {
    private(set) var catalog: StarCatalog?
    private(set) var constellations: [Constellation] = []
    private(set) var isLoading = false

    func loadIfNeeded() {
        guard catalog == nil, !isLoading else { return }
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let stars = Self.loadBundledStars()
            let constellations = ConstellationData.loadBundled()
            await MainActor.run {
                self.catalog = StarCatalog(stars: stars)
                self.constellations = constellations
                self.isLoading = false
            }
        }
    }

    private nonisolated static func loadBundledStars() -> [Star] {
        guard let url = Bundle.main.url(forResource: "stars", withExtension: "bin"),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let stars = try? BinaryStarCatalog.parse(data) else {
            return []
        }
        return stars
    }
}
