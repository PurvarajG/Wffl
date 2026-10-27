// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Wffl",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.0"),
        // Runs Atlas's BAPS-tuned Whisper (Core ML), the same engine and version Atlas measured it with.
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.0"),
        // In-app updates. Pinned to 2.10.0 (13 Sep 2026), the newest release public for over two weeks; 2.10.1 is only days old.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(
            name: "CWhisper",
            path: "Sources/CWhisper"
        ),
        .executableTarget(
            name: "Wffl",
            dependencies: [
                "CWhisper",
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Wffl",
            resources: [.copy("Resources")],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .unsafeFlags(["-L", "vendor/lib"]),
                // bundle.sh embeds Sparkle.framework in Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedLibrary("c++")
            ]
        ),
        // Design prototype for app v2 (two directions, sample data only). Not shipped.
        .executableTarget(
            name: "WfflPrototype",
            path: "Sources/WfflPrototype",
            resources: [.copy("Fonts")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "WfflTests",
            dependencies: ["Wffl"],
            path: "Tests/WfflTests",
            exclude: ["Fixtures"]
        )
    ]
)
