// swift-tools-version: 5.9
//
// Lichen — SwiftPM 清单（应用框架骨架，skeleton only）。
// 仅声明模块边界，零第三方依赖；不包含任何真实网络、鉴权或终端仿真实现。

import PackageDescription

let package = Package(
    name: "Lichen",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "LichenCore", targets: ["LichenCore"]),
        .library(name: "LichenApp", targets: ["LichenApp"])
    ],
    targets: [
        .target(
            name: "LichenCore",
            path: "Sources/LichenCore"
        ),
        .target(
            name: "LichenApp",
            dependencies: ["LichenCore"],
            path: "Sources/LichenApp"
        ),
        .testTarget(
            name: "LichenCoreTests",
            dependencies: ["LichenCore"],
            path: "Tests/LichenCoreTests"
        )
    ]
)
