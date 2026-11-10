// swift-tools-version:6.0
import PackageDescription

// KiriKiriCore.xcframework 由 Tools/构建KiriKiri.sh 从 krkr2（MIT）编译。
let package = Package(
    name: "KiriKiri",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "KiriKiri", targets: ["KiriKiri", "PaperVNMPEG"]),
    ],
    targets: [
        .binaryTarget(name: "KiriKiriCore", path: "KiriKiriCore.xcframework"),
        // MPEG-1 影片：pl_mpeg（MIT）。调试版也要优化，否则放不到实时
        .target(
            name: "PaperVNMPEG",
            exclude: ["PL_MPEG_COMMIT"],
            cSettings: [.unsafeFlags(["-O3"])]
        ),
        .target(
            name: "KiriKiri",
            dependencies: ["KiriKiriCore"],
            linkerSettings: [
                .linkedFramework("OpenGLES"),
                .linkedFramework("OpenAL"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreMotion"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("GameController"),
                .linkedFramework("Security"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("UIKit"),
                .linkedLibrary("z"),
                .linkedLibrary("sqlite3"),
                .linkedLibrary("c++"),
            ]
        ),
    ]
)
