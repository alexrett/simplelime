// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SimpleLime",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SimpleLime", targets: ["SimpleLime"])
    ],
    targets: [
        .executableTarget(
            name: "SimpleLime",
            path: "Sources/SimpleLime"
        )
    ]
)
