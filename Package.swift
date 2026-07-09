// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Meetily",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "CWhisper",
            path: "Sources/CWhisper"
        ),
        .executableTarget(
            name: "Meetily",
            dependencies: ["CWhisper"],
            path: "Sources/Meetily",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .unsafeFlags(["-L", "vendor/lib"]),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedLibrary("c++")
            ]
        )
    ]
)
