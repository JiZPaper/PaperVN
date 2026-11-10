// swift-tools-version:6.0
import PackageDescription

// SiglusCore.xcframework 由 Tools/构建Siglus.sh 从 siglus_rs（MPL-2.0）编译。
let package = Package(
    name: "Siglus",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "Siglus", targets: ["Siglus"]),
    ],
    targets: [
        .binaryTarget(name: "SiglusCore", path: "SiglusCore.xcframework"),
        .target(
            name: "Siglus",
            dependencies: ["SiglusCore"],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("UIKit"),
                .linkedLibrary("c++"),
            ]
        ),
    ]
)
