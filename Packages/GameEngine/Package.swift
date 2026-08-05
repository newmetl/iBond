// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GameEngine",
    products: [
        .library(name: "GameEngine", targets: ["GameEngine"])
    ],
    targets: [
        .target(name: "GameEngine"),
        .testTarget(name: "GameEngineTests", dependencies: ["GameEngine"])
    ]
)
