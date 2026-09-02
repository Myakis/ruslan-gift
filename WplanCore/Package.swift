// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WplanCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "WplanCore", targets: ["WplanCore"])
    ],
    targets: [
        .target(name: "WplanCore"),
        .testTarget(name: "WplanCoreTests", dependencies: ["WplanCore"])
    ]
)
