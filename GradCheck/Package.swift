// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "GradCheck",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "GradCheck", targets: ["GradCheck"])
    ],
    targets: [
        .executableTarget(
            name: "GradCheck",
            path: "Sources/GradCheck"
        ),
        .testTarget(
            name: "GradCheckTests",
            dependencies: ["GradCheck"],
            path: "Tests/GradCheckTests"
        )
    ]
)

