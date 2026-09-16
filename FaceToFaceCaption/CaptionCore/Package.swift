// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "CaptionCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CaptionCore", targets: ["CaptionCore"]),
    ],
    targets: [
        .target(name: "CaptionCore"),
        .testTarget(name: "CaptionCoreTests", dependencies: ["CaptionCore"]),
    ]
)
