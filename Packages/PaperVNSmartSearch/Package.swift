// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PaperVNSmartSearch",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "PaperVNSmartSearch", targets: ["PaperVNSmartSearch"]),
    ],
    targets: [
        .target(name: "PaperVNSmartSearch"),
        .testTarget(
            name: "PaperVNSmartSearchTests",
            dependencies: ["PaperVNSmartSearch"]
        ),
    ]
)
