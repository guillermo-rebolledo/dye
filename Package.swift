// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FilmEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "FilmEngine", targets: ["FilmEngine"])],
    targets: [
        .target(name: "FilmEngine", resources: [.copy("Metal"), .copy("Profiles/Calibration"), .copy("Catalogue")]),
        .testTarget(name: "FilmEngineTests", dependencies: ["FilmEngine"], resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v6]
)
