// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SimpleLime",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SimpleLime", targets: ["SimpleLime"])
    ],
    dependencies: [
        .package(url: "https://github.com/krzyzanowskim/STTextView", from: "2.3.10")
    ],
    targets: [
        .executableTarget(
            name: "SimpleLime",
            dependencies: [
                .product(name: "STTextView", package: "STTextView")
            ],
            path: "Sources/SimpleLime"
        ),
        .testTarget(
            name: "SimpleLimeTests",
            dependencies: ["SimpleLime"],
            path: "Tests/SimpleLimeTests"
        )
    ]
)
