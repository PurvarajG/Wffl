// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Wffl",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.0"),
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
            ],
            path: "Sources/Wffl",
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
        ),
        .testTarget(
            name: "WfflTests",
            dependencies: ["Wffl"],
            path: "Tests/WfflTests"
        )
    ]
)
