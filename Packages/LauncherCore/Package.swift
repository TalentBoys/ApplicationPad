// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LauncherCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "LauncherCore",
            targets: ["LauncherCore"]),
    ],
    targets: [
        .target(
            name: "LauncherCore"),
        .testTarget(
            name: "LauncherCoreTests",
            dependencies: ["LauncherCore"]),
    ]
)
