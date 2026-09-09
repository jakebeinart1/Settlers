// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CatanAI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CatanAI", targets: ["CatanAI"])
    ],
    dependencies: [
        .package(path: "../CatanEngine")
    ],
    targets: [
        .target(name: "CatanAI", dependencies: ["CatanEngine"]),
        // Headless seeded self-play harness. Deliberately a target and NOT a
        // `products:` entry: the iOS app links this package by package name
        // (`project.yml` -> `dependencies: - package: CatanAI`), so adding a
        // second product would change what XcodeGen resolves and show up as
        // project drift in `scripts/gate.sh`. SwiftPM synthesizes an implicit
        // executable product for an `.executableTarget`, which is all
        // `swift run --package-path Packages/CatanAI sim` needs.
        .executableTarget(name: "sim", dependencies: ["CatanAI", "CatanEngine"]),
        // Offline enrichment of retained decisions; no policy/session loop.
        .executableTarget(name: "trade-review", dependencies: ["CatanAI", "CatanEngine"]),
        .testTarget(name: "CatanAITests", dependencies: ["CatanAI"])
    ]
)
