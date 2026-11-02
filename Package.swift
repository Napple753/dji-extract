// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DJIExtract",
    platforms: [
        .iOS(.v26),
        // macOS is supported only so that the core logic and media pipeline
        // can be built and tested from the command line.
        .macOS(.v26),
    ],
    products: [
        .library(name: "DJIExtractCore", targets: ["DJIExtractCore"]),
        .library(name: "DJIExtractKit", targets: ["DJIExtractKit"]),
        .library(name: "DJIExtractUI", targets: ["DJIExtractUI"]),
    ],
    targets: [
        // Pure logic, Foundation only (no AVFoundation).
        .target(name: "DJIExtractCore"),
        // Media pipeline: metadata, frame/clip/Live Photo export, Photos, camera folder access.
        .target(name: "DJIExtractKit", dependencies: ["DJIExtractCore"]),
        // SwiftUI screens. The iOS app target (App/) only hosts `RootView`.
        .target(name: "DJIExtractUI", dependencies: ["DJIExtractCore", "DJIExtractKit"]),
        .testTarget(name: "DJIExtractCoreTests", dependencies: ["DJIExtractCore"]),
        .testTarget(name: "DJIExtractKitTests", dependencies: ["DJIExtractKit"]),
    ]
)
