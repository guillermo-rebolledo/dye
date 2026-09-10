// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FilmEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "FilmEngine", targets: ["FilmEngine"]),
               .executable(name: "ProfileBaker", targets: ["ProfileBaker"])],
    targets: [
        .target(name: "FilmEngine", resources: [.copy("Metal"), .copy("Catalogue")]),
        .executableTarget(name: "ProfileBaker", dependencies: ["FilmEngine"], path: "ProfileBaker"),
        .testTarget(name: "FilmEngineTests", dependencies: ["FilmEngine", .target(name: "ProfileBaker", condition: .when(platforms: [.macOS]))], resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v6]
)
