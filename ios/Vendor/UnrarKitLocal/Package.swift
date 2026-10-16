// swift-tools-version:5.3
// vendored UnrarKit：官方 UnRAR 6.12 源码（RAR4 + RAR5 完整支持）
// SPM 清单结构参照社区验证过的 ZHK1024/UnrarKit-Swift-Package。
//
// 布局说明：
//   - UnrarKit 目标：URKArchive（ObjC++ 包装）+ URKFileInfo + unrar/dll.cpp
//     公共头文件 = Classes/（URKArchive.h / URKFileInfo.h / UnrarKitMacros.h）
//   - UnrarKitCategories 目标：NSString+UnrarKit 类别（URKArchive.mm 会调用它，
//     必须一起编译，否则运行时 unrecognized selector）
//   - 消费方 import 的是目标模块名 `UnrarKit`（product 名 UnrarKitLocal）

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
                "LICENSE"
            ],
            sources: [
                "Classes/URKArchive.mm",
                "Classes/URKFileInfo.m",
                "Libraries/unrar/dll.cpp"
            ],
            publicHeadersPath: "Classes",
            // 注意：不用 unsafeFlags（-Wno-everything）——SwiftPM 对依赖包的
            // unsafe build flags 有限制，会直接让 swift test 失败。
            // unrar 源码的告警不致命，容忍即可。
            cxxSettings: [
                .headerSearchPath("Libraries/unrar"),
                .headerSearchPath("Classes"),
                .headerSearchPath("Classes/Categories"),
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
                .define("LARGEFILE_SOURCE")
            ]
        )
    ],
    cxxLanguageStandard: .cxx11
)
