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
    targets: [
        .target(name: "CelestialCore"),
        .testTarget(
            name: "CelestialCoreTests",
            dependencies: ["CelestialCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
