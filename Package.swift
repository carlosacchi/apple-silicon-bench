// swift-tools-version:5.9
import PackageDescription

let version = "2.0.0"

let package = Package(
    name: "osx-bench",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "osx-bench", targets: ["osx-bench"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "osx-bench",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/osx-bench",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
    ]
)
