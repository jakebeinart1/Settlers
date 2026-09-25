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
        // Trade behaviour on sampled positions, without playing games out.
        .executableTarget(name: "trade-bench", dependencies: ["CatanAI", "CatanEngine"]),
        // A person model from recorded games, and its ghost. Not a product, for
        // the reason `sim` is not.
        .executableTarget(name: "ghost", dependencies: ["CatanAI", "CatanEngine"]),
        .testTarget(name: "CatanAITests", dependencies: ["CatanAI"])
    ]
)
