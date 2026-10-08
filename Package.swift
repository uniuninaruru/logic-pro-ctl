// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "logicctl",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "logicctl", targets: ["logicctl"]),
        .executable(name: "logicd", targets: ["logicd"]),
        .executable(name: "logicmcp", targets: ["LogicMCPCLI"]),
    ],
    targets: [
        .target(name: "LogicCore"),
        .target(name: "LogicMCP", dependencies: ["LogicCore"]),
        .executableTarget(name: "logicctl", dependencies: ["LogicCore"]),
        .executableTarget(name: "logicd", dependencies: ["LogicCore"]),
        .executableTarget(name: "LogicMCPCLI", dependencies: ["LogicMCP"]),
        .testTarget(name: "LogicCoreTests", dependencies: ["LogicCore"]),
        .testTarget(name: "LogicMCPTests", dependencies: ["LogicMCP", "LogicCore"]),
    ]
)
