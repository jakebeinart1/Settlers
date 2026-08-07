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
        .testTarget(name: "CatanAITests", dependencies: ["CatanAI"])
    ]
)
