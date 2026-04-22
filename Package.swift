// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZentaoBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "ZentaoBar",
            targets: ["ZentaoBar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "ZentaoBar",
            path: "Sources/ZentaoBar"
        )
    ]
)
