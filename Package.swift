// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DualSenseAgentBridge",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "DualSenseBridgeCore",
            targets: ["DualSenseBridgeCore"]
        ),
        .executable(
            name: "dualsense-bridge",
            targets: ["dualsense-bridge"]
        ),
    ],
    targets: [
        .target(name: "DualSenseBridgeCore"),
        .executableTarget(
            name: "dualsense-bridge",
            dependencies: ["DualSenseBridgeCore"]
        ),
        .testTarget(
            name: "DualSenseBridgeCoreTests",
            dependencies: ["DualSenseBridgeCore"]
        ),
    ]
)

