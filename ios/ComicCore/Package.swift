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
    dependencies: [
        // ZIP / CBZ：纯 Swift 实现的 ZIP 读写（按条目随机访问）
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
        // vendored UnRAR 6.12（RAR4 + RAR5）
        .package(path: "../Vendor/UnrarKitLocal")
    ],
    targets: [
        .target(
            name: "ComicReaderCore",
            dependencies: [
                "ZIPFoundation",
                .product(name: "UnrarKitLocal", package: "UnrarKitLocal")
            ],
            path: "Sources/ComicReaderCore"
        ),
        .testTarget(
            name: "ComicReaderCoreTests",
            dependencies: ["ComicReaderCore"],
            path: "Tests/ComicReaderCoreTests"
        )
    ]
)
