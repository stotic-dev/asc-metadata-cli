// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "asc-metadata-cli",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "asc-metadata-cli", targets: ["asc-metadata-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/AvdLee/appstoreconnect-swift-sdk.git", from: "4.4.0"),
    ],
    targets: [
        .target(
            name: "ASCMetadataKit",
            dependencies: [
                .product(name: "AppStoreConnect-Swift-SDK", package: "appstoreconnect-swift-sdk"),
            ]
        ),
        .executableTarget(
            name: "asc-metadata-cli",
            dependencies: [
                "ASCMetadataKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "ASCMetadataKitTests",
            dependencies: ["ASCMetadataKit"]
        ),
    ]
)
