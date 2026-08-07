// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CatanEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CatanEngine", targets: ["CatanEngine"])
    ],
    targets: [
        .target(name: "CatanEngine"),
        .testTarget(name: "CatanEngineTests", dependencies: ["CatanEngine"])
    ]
)
