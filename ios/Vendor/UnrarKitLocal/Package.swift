// swift-tools-version:5.3
// vendored UnrarKit：官方 UnRAR 6.12 源码（RAR4 + RAR5 完整支持）
// SPM 清单结构参照社区验证过的 ZHK1024/UnrarKit-Swift-Package，并按 SwiftPM
// 的头文件布局规则调整：
//   - publicHeadersPath（Classes/）必须只含头文件，不能有子目录 ——
//     类别包装（NSString+UnrarKit）因此移到包根的 Categories/
//   - 消费方 import 的是目标模块名 `UnrarKit`（product 名 UnrarKitLocal）
//
// 不用 unsafeFlags（-Wno-everything）：SwiftPM 对依赖包的 unsafe build flags
// 有限制会让 swift test 失败；unrar 源码的告警不致命，容忍即可。

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
                "Categories",
                "LICENSE"
            ],
            sources: [
                "Classes/URKArchive.mm",
                "Classes/URKFileInfo.m",
                "Libraries/unrar/dll.cpp"
            ],
            publicHeadersPath: "Classes",
            cxxSettings: [
                .headerSearchPath("Libraries/unrar"),
                .headerSearchPath("Classes"),
                .headerSearchPath("Categories"),
                .define("RARDLL"),
                .define("UNRAR"),
                .define("_UNIX"),
                .define("_FILE_OFFSET_BITS", to: "64"),
                .define("LARGEFILE_SOURCE")
            ],
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
        .target(
            name: "UnrarKitCategories",
            dependencies: ["UnrarKit"],
            path: "Categories",
            sources: [
                "NSString+UnrarKit.mm"
            ],
            cxxSettings: [
                .headerSearchPath("../Libraries/unrar"),
                .headerSearchPath("../Classes"),
                .define("RARDLL"),
                .define("UNRAR"),
                .define("_UNIX"),
                .define("_FILE_OFFSET_BITS", to: "64"),
                .define("LARGEFILE_SOURCE")
            ]
        )
    ],
    cxxLanguageStandard: .cxx11
)
