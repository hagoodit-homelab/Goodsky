// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GoodskyKit",
    platforms: [.iOS("26.0"), .watchOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "GoodskyCore", targets: ["GoodskyCore"]),
        .library(name: "GoodskyWeather", targets: ["GoodskyWeather"]),
    ],
    targets: [
        // Pure Foundation logic. Builds and tests on Linux too (see .github/workflows).
        .target(name: "GoodskyCore"),
        // Apple-only glue: WeatherKit, CoreLocation, App Group storage.
        // Every file is wrapped in `#if canImport(WeatherKit)` so `swift test` works on Linux.
        .target(
            name: "GoodskyWeather",
            dependencies: ["GoodskyCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "GoodskyCoreTests", dependencies: ["GoodskyCore"]),
    ]
)
