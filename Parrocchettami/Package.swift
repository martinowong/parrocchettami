// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Parrocchettami",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Parrocchettami",
            path: "Sources/Parrocchettami"
        ),
        .testTarget(
            name: "ParrocchettamiTests",
            dependencies: ["Parrocchettami"],
            path: "Tests/ParrocchettamiTests"
        )
    ]
)
