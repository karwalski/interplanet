// swift-tools-version:5.9
import PackageDescription

// CryptoKit ships with Apple platforms. On Linux the same API comes from
// apple/swift-crypto (module `Crypto`); the sources pick whichever exists.
let package = Package(
    name: "InterplanetLTX",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "InterplanetLTX", targets: ["InterplanetLTX"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0" ..< "4.0.0"),
    ],
    targets: [
        .target(
            name: "InterplanetLTX",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto",
                         condition: .when(platforms: [.linux, .windows, .android, .wasi])),
            ],
            path: "Sources/InterplanetLTX"
        ),
        .executableTarget(
            name: "InterplanetLTXTests",
            dependencies: ["InterplanetLTX"],
            path: "Tests/InterplanetLTXTests"
        ),
    ]
)
