// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ComicReaderCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "ComicReaderCore", targets: ["ComicReaderCore"])
    ],
    targets: [
        .target(
            name: "ComicReaderCore",
            path: "Sources/ComicReaderCore"
        ),
        .testTarget(
            name: "ComicReaderCoreTests",
            dependencies: ["ComicReaderCore"],
            path: "Tests/ComicReaderCoreTests"
        )
    ]
)
