// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LogicScreen",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LogicScreen", targets: ["LogicScreen"]),
        .executable(name: "LogicScreenProbe", targets: ["LogicScreenProbe"])
    ],
    targets: [
        .target(name: "LogicScreenCore"),
        .target(name: "LogicScreenPlatform", dependencies: ["LogicScreenCore"]),
        .executableTarget(name: "LogicScreen", dependencies: ["LogicScreenCore", "LogicScreenPlatform"]),
        .executableTarget(name: "LogicScreenProbe", dependencies: ["LogicScreenCore", "LogicScreenPlatform"]),
        .testTarget(name: "LogicScreenCoreTests", dependencies: ["LogicScreenCore"])
    ],
    swiftLanguageModes: [.v5]
)
