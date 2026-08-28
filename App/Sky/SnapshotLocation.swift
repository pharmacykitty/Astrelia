import Foundation

/// Debug-only (`-snapshotLocation <lat> <lon>`, degrees): a fixed observer position
/// for App Store screenshot runs. With it set, the location stack skips the system
/// permission prompt entirely (which otherwise covers every capture in the
/// simulator) and every screenshot is reproducible. Production is untouched — the
/// argument is never present outside a snapshot run. Sibling of `-snapshotSky`,
/// which does the same for device attitude.
enum SnapshotLocation {
    static let coordinate: (latitude: Double, longitude: Double)? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-snapshotLocation"),
              i + 2 < args.count,
              let latitude = Double(args[i + 1]),
              let longitude = Double(args[i + 2]) else { return nil }
        return (latitude, longitude)
    }()
}
