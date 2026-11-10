// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Paper Intelligence",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "PaperIntelligence", targets: ["PaperIntelligence"]),
    ],
    targets: [
        .target(name: "PaperIntelligence"),
        .testTarget(
            name: "PaperIntelligenceTests",
            dependencies: ["PaperIntelligence"]
        ),
    ]
)
