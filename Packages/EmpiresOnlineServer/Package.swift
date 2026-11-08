// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "EmpiresOnlineServer",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "empires-online-server", targets: ["EmpiresOnlineServer"])],
    dependencies: [
        .package(path: "../EmpiresOnline"),
        .package(url: "https://github.com/vapor/vapor.git", exact: "4.122.3"),
        .package(url: "https://github.com/swift-server-community/APNSwift.git", exact: "8.0.0", traits: [])
    ],
    targets: [
        .executableTarget(
            name: "EmpiresOnlineServer",
            dependencies: [
                .product(name: "EmpiresOnline", package: "EmpiresOnline"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "APNS", package: "APNSwift"),
                .product(name: "APNSCore", package: "APNSwift")
            ]
        ),
        .testTarget(
            name: "EmpiresOnlineServerTests",
            dependencies: [
                "EmpiresOnlineServer",
                .product(name: "EmpiresOnline", package: "EmpiresOnline"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "APNSCore", package: "APNSwift"),
                .product(name: "VaporTesting", package: "vapor")
            ]
        )
    ]
)
