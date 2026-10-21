// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HiroIntelligence",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "HiroIntelligence", targets: ["HiroIntelligence"]),
    ],
    targets: [
        .target(name: "HiroIntelligence"),
        .testTarget(
            name: "HiroIntelligenceTests",
            dependencies: ["HiroIntelligence"]
        ),
    ]
)
