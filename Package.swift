// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "crap4swift",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "crap4swift", targets: ["crap4swift"]),
        .library(name: "crap4swiftCore", targets: ["crap4swiftCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", .upToNextMinor(from: "600.0.1")),
    ],
    targets: [
        .target(
            name: "crap4swiftCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .executableTarget(
            name: "crap4swift",
            dependencies: ["crap4swiftCore"]
        ),
        .testTarget(
            name: "crap4swiftTests",
            dependencies: ["crap4swiftCore"]
        ),
    ]
)
