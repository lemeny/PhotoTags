// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhotoTagsCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "PhotoTagsCore", targets: ["PhotoTagsCore"])
    ],
    targets: [
        .target(name: "PhotoTagsCore"),
        .testTarget(name: "PhotoTagsCoreTests", dependencies: ["PhotoTagsCore"])
    ]
)
