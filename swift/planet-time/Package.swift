// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InterplanetTime",
    products: [
        .library(name: "InterplanetTime", targets: ["InterplanetTime"]),
        .executable(name: "RunTests", targets: ["RunTests"]),
    ],
    targets: [
        .target(name: "InterplanetTime", path: "Sources/InterplanetTime"),
        // XCTest-based tests (require Xcode.app, not just CLT)
        .testTarget(
            name: "InterplanetTimeTests",
            dependencies: ["InterplanetTime"],
            path: "Tests/InterplanetTimeTests"
        ),
        // Standalone test runner — works with Command Line Tools only
        .executableTarget(
            name: "RunTests",
            dependencies: ["InterplanetTime"],
            path: "Sources/RunTests"
        ),
    ]
)
