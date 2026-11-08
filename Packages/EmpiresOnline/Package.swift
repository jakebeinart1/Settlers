// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EmpiresOnline",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "EmpiresOnline", targets: ["EmpiresOnline"])],
    dependencies: [
        .package(path: "../CatanEngine"),
        .package(path: "../CatanAI"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.12.3")
    ],
    targets: [
        .target(name: "EmpiresOnline", dependencies: [
            "CatanEngine", "CatanAI", .product(name: "Crypto", package: "swift-crypto")
        ]),
        .testTarget(name: "EmpiresOnlineTests", dependencies: ["EmpiresOnline", "CatanEngine"])
    ]
)
