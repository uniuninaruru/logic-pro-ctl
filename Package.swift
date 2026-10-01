// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "logicctl",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "logicctl", targets: ["logicctl"]),
        .executable(name: "logicd", targets: ["logicd"]),
    ],
    targets: [
        .target(name: "LogicCore"),
        .executableTarget(name: "logicctl", dependencies: ["LogicCore"]),
        .executableTarget(name: "logicd", dependencies: ["LogicCore"]),
        .testTarget(name: "LogicCoreTests", dependencies: ["LogicCore"]),
    ]
)
