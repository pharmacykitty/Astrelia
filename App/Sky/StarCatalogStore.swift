import Foundation
import CelestialCore

/// Loads the bundled HYG star catalog (naked-eye subset, mag ≤ 6.5) once, off the
/// main thread, and hands it to the UI.
@MainActor
@Observable
final class StarCatalogStore {
    private(set) var catalog: StarCatalog?
    private(set) var isLoading = false

    func loadIfNeeded() {
        guard catalog == nil, !isLoading else { return }
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let stars = Self.loadBundledStars()
            await MainActor.run {
                self.catalog = StarCatalog(stars: stars)
                self.isLoading = false
            }
        }
    }

    private nonisolated static func loadBundledStars() -> [Star] {
        guard let url = Bundle.main.url(forResource: "hyg_naked_eye", withExtension: "csv"),
              let data = try? Data(contentsOf: url),
              let stars = try? HYGCatalog.parse(csv: data) else {
            return []
        }
        return stars
    }
}
