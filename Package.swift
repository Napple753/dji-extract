// swift-tools-version: 6.2
import PackageDescription

// SwiftUI's macro plugin ships only with Xcode, so the UI target cannot be built with the
// Command Line Tools alone. scripts/test.sh sets this to leave it out.
let includeUI = Context.environment["DJI_EXTRACT_SKIP_UI"] == nil

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
    ] + (includeUI ? [.library(name: "DJIExtractUI", targets: ["DJIExtractUI"])] : []),
    targets: [
        // Pure logic, Foundation only (no AVFoundation).
        .target(name: "DJIExtractCore"),
        // Media pipeline: metadata, frame/clip/Live Photo export, Photos, camera folder access.
        .target(name: "DJIExtractKit", dependencies: ["DJIExtractCore"]),
        .testTarget(name: "DJIExtractCoreTests", dependencies: ["DJIExtractCore"]),
        .testTarget(name: "DJIExtractKitTests", dependencies: ["DJIExtractKit"]),
    ] + (includeUI ? [
        // SwiftUI screens. The iOS app target (App/) only hosts `RootView`.
        .target(name: "DJIExtractUI", dependencies: ["DJIExtractCore", "DJIExtractKit"]),
    ] : [])
)
