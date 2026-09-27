// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AppleMusicRemoteMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "AppleMusicRemoteMac",
            targets: ["AppleMusicRemoteMac"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "AppleMusicRemoteMac",
            dependencies: [],
            path: "Sources/AppleMusicRemoteMac"
        ),
        .testTarget(
            name: "AppleMusicRemoteMacTests",
            dependencies: ["AppleMusicRemoteMac"],
            path: "Tests/AppleMusicRemoteMacTests"
        )
    ]
)
