// swift-tools-version:5.9
// Interop driver for swift/ltx (see scripts/interop/run.js).
import PackageDescription

let package = Package(
    name: "Driver",
    platforms: [.macOS(.v12)],
    dependencies: [.package(path: "../../../../swift/ltx")],
    targets: [
        .executableTarget(
            name: "Driver",
            dependencies: [.product(name: "InterplanetLTX", package: "ltx")],
            path: "Sources/Driver"
        ),
    ]
)
