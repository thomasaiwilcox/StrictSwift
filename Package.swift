// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "StrictSwift",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "strictswift", targets: ["StrictSwiftCLI"]),
        .executable(name: "strictswift-lsp", targets: ["StrictSwiftLSP"]),
        .library(name: "StrictSwiftCore", targets: ["StrictSwiftCore"]),
        .plugin(name: "StrictSwiftPlugin", targets: ["StrictSwiftPlugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "600.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "StrictSwiftCLI",
            dependencies: [
                "StrictSwiftCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "StrictSwiftCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "SystemPackage", package: "swift-system"),
            ]
        ),
        .plugin(
            name: "StrictSwiftPlugin",
            capability: .buildTool(),
            dependencies: [
                .target(name: "StrictSwiftCLI")
            ]
        ),
        .executableTarget(
            name: "StrictSwiftLSP",
            dependencies: [
                "StrictSwiftCore",
            ],
            path: "Sources/StrictSwiftLSP"
        ),
        .testTarget(
            name: "StrictSwiftTests",
            dependencies: ["StrictSwiftCore"],
            path: "Tests/StrictSwiftTests"
        ),
    ]
)