// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SimpleLime",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SimpleLime", targets: ["SimpleLime"]),
        .executable(name: "SimpleLimeRelay", targets: ["SimpleLimeRelay"]),
        .library(name: "SimpleLimeRelayCore", targets: ["SimpleLimeRelayCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/krzyzanowskim/STTextView", from: "2.3.10"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.13.0")
    ],
    targets: [
        .executableTarget(
            name: "SimpleLime",
            dependencies: [
                .product(name: "STTextView", package: "STTextView"),
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/SimpleLime"
        ),
        .target(
            name: "SimpleLimeRelayCore",
            path: "Sources/SimpleLimeRelayCore"
        ),
        .executableTarget(
            name: "SimpleLimeRelay",
            dependencies: ["SimpleLimeRelayCore"],
            path: "Sources/SimpleLimeRelay"
        ),
        .testTarget(
            name: "SimpleLimeTests",
            dependencies: ["SimpleLime", "SimpleLimeRelayCore"],
            path: "Tests/SimpleLimeTests"
        )
    ]
)
