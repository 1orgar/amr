// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AppleMusicRemoteMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "AppleMusicRemoteMac",
            targets: ["AppleMusicRemoteMac"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CAtomicPrimitives",
            path: "Sources/CAtomicPrimitives",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "AppleMusicRemoteMac",
            dependencies: ["CAtomicPrimitives"],
            path: "Sources/AppleMusicRemoteMac",
            resources: [
                .copy("DSP/Oversampling/Shaders/PolyphaseOverlapSave.metal")
            ]
        ),
        .testTarget(
            name: "AppleMusicRemoteMacTests",
            dependencies: ["AppleMusicRemoteMac"],
            path: "Tests/AppleMusicRemoteMacTests"
        )
    ]
)
