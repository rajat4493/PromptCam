// swift-tools-version: 6.0
import PackageDescription

// PromptCamCore only.
//
// The iOS application layer (Sources/PromptCamiOS) is deliberately NOT a
// target of this package: it imports SwiftUI, AVFoundation, SwiftData and
// Photos and can only be compiled by Xcode against the iOS SDK. It is built
// through `project.yml` (XcodeGen) instead. See docs/MAC_VALIDATION.md.
//
// This package is platform-independent Swift and is intended to compile and
// test on Linux as well as macOS.
let package = Package(
    name: "PromptCamCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v13)
    ],
    products: [
        .library(name: "PromptCamCore", targets: ["PromptCamCore"])
    ],
    targets: [
        .target(
            name: "PromptCamCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PromptCamCoreTests",
            dependencies: ["PromptCamCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
