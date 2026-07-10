// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ork",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Ork",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/Ork",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "OrkTests",
            dependencies: ["Ork"],
            path: "Tests/OrkTests"
        )
    ]
)
