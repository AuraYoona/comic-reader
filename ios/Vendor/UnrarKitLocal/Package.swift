// swift-tools-version:5.3
// vendored UnrarKit：官方 UnRAR 6.12 源码（RAR4 + RAR5 完整支持）
// SPM 清单结构参照社区验证过的 ZHK1024/UnrarKit-Swift-Package。

import PackageDescription

let package = Package(
    name: "UnrarKitLocal",
    platforms: [
        .iOS(.v12),
        .macOS(.v10_13)
    ],
    products: [
        .library(
            name: "UnrarKitLocal",
            targets: ["UnrarKit", "UnrarKitCategories"]
        ),
    ],
    targets: [
        .target(
            name: "UnrarKit",
            path: ".",
            exclude: [
                "Classes/Categories",
                "LICENSE",
                "Package.swift"
            ],
            sources: [
                "Classes/URKArchive.mm",
                "Classes/URKFileInfo.m",
                "Libraries/unrar/dll.cpp"
            ],
            publicHeadersPath: "Classes/Categories",
            cxxSettings: [
                .headerSearchPath("Libraries/unrar"),
                .headerSearchPath("Classes"),
                .define("RARDLL"),
                .define("UNRAR"),
                .define("_UNIX"),
                .define("_FILE_OFFSET_BITS", to: "64"),
                .define("LARGEFILE_SOURCE"),
                .unsafeFlags(["-Wno-everything"])
            ],
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
        .target(
            name: "UnrarKitCategories",
            dependencies: ["UnrarKit"],
            path: "Classes/Categories",
            sources: [
                "NSString+UnrarKit.mm"
            ],
            cxxSettings: [
                .headerSearchPath("../../Libraries/unrar"),
                .headerSearchPath(".."),
                .define("RARDLL"),
                .define("UNRAR"),
                .define("_UNIX"),
                .define("_FILE_OFFSET_BITS", to: "64"),
                .define("LARGEFILE_SOURCE"),
                .unsafeFlags(["-Wno-everything"])
            ]
        )
    ],
    cxxLanguageStandard: .cxx11
)
