// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "asc-metadata-cli",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "ASCMetadataKit"),
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
