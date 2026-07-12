// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ork",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.0"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
        .package(url: "https://github.com/swift-server/RediStack.git", from: "1.6.0")
    ],
    targets: [
        .executableTarget(
            name: "Ork",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "RediStack", package: "RediStack")
            ],
            path: "Sources/Ork",
            resources: [.process("Resources")]
        ),
        .target(
            name: "OrkMCPCore",
            path: "Sources/OrkMCPCore"
        ),
        .executableTarget(
            name: "ork-mcp",
            dependencies: ["OrkMCPCore"],
            path: "Sources/OrkMCP"
        ),
        .testTarget(
            name: "OrkTests",
            dependencies: ["Ork", "OrkMCPCore"],
            path: "Tests/OrkTests"
        )
    ]
)
