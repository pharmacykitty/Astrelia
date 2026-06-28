// swift-tools-version: 6.0
import PackageDescription

// CelestialCore is the platform-agnostic astronomy engine for Astrolabe.
// Swift 6 language mode is set package-wide, which turns on *complete* strict
// concurrency checking for every target. No UIKit/SwiftUI/sensor code lives here.
let package = Package(
    name: "CelestialCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CelestialCore", targets: ["CelestialCore"]),
    ],
    dependencies: [
        // SwiftAA (MIT) supplies the planet ephemeris (Mercury–Pluto) via Meeus'
        // algorithms. We keep "rolled our own" for time/coords/Sun/Moon and use
        // SwiftAA only as the planetary-position engine, per the roadmap's
        // "reassess SwiftAA there [planets]" note. No UIKit/SwiftUI; pure compute.
        .package(url: "https://github.com/onekiloparsec/SwiftAA.git", from: "3.0.1"),
    ],
    targets: [
        .target(
            name: "CelestialCore",
            dependencies: [
                .product(name: "SwiftAA", package: "SwiftAA"),
                // AABridge: the C/AA+ layer. SwiftAA's `Pluto` can't return a
                // geocentric position (its `planetStrict` rejects Pluto), so we
                // reach the heliocentric Pluto/Earth functions directly and do the
                // geocentric reduction ourselves.
                .product(name: "AABridge", package: "SwiftAA"),
            ]
        ),
        .testTarget(
            name: "CelestialCoreTests",
            dependencies: ["CelestialCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
