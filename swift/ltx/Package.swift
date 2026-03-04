// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "InterplanetLTX",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "InterplanetLTX", targets: ["InterplanetLTX"]),
    ],
    targets: [
        .target(name: "InterplanetLTX", path: "Sources/InterplanetLTX"),
        .executableTarget(
            name: "InterplanetLTXTests",
            dependencies: ["InterplanetLTX"],
            path: "Tests/InterplanetLTXTests"
        ),
    ]
)
