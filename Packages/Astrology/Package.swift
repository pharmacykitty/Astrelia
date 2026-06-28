// swift-tools-version: 6.0
import PackageDescription

// Astrology is the symbolic layer, kept strictly separate from the astrophysics.
// It depends on CelestialCore for time/coordinate/ephemeris math and adds the
// astrological constructs on top: zodiac, houses, aspects, charts. No UIKit/
// SwiftUI/sensor code lives here. Swift 6 language mode → complete strict
// concurrency for every target.
let package = Package(
    name: "Astrology",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "Astrology", targets: ["Astrology"]),
    ],
    dependencies: [
        .package(path: "../CelestialCore"),
    ],
    targets: [
        .target(
            name: "Astrology",
            dependencies: ["CelestialCore"]
        ),
        .testTarget(
            name: "AstrologyTests",
            dependencies: ["Astrology"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
