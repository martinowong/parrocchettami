// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Parrocchettami",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4"),
    ],
    targets: [
        .executableTarget(
            name: "Parrocchettami",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Parrocchettami",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "ParrocchettamiTests",
            dependencies: ["Parrocchettami"],
            path: "Tests/ParrocchettamiTests"
        )
    ]
)
