// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MicStreamer",
    platforms: [.macOS("14.2")],
    products: [
        .executable(name: "MicStreamer", targets: ["MicStreamer"])
    ],
    targets: [
        .executableTarget(
            name: "MicStreamer",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio")
            ]
        )
    ]
)
