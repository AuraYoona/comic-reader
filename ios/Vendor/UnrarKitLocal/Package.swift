// swift-tools-version:5.3
// vendored UnrarKit：官方 UnRAR 6.12 源码（RAR4 + RAR5 完整支持）。
//
// 单一 target 设计（对 ZHK1024 版本做了合并）：
//   - 四个源文件全部编译进 UnrarKit 一个归档：URKArchive.mm（ObjC++ 包装）、
//     URKFileInfo.m、NSString+UnrarKit.mm（类别，URKFileInfo 运行时依赖）、
//     unrar/dll.cpp。多 target 曾在 CI 触发 repeated ObjC 符号链接错误，
//     合并后链接面上只有一个归档，机制上消除该类问题。
//   - publicHeadersPath（Classes/）只允许平铺头文件：raros.hpp 与 dll.hpp
//     是从 Libraries/unrar/ 镜像进来的（公共头依赖它们，而 SPM 不会把
//     unrar 的 include 目录暴露给 clang 模块构建）。
//   - 不用 unsafeFlags：SwiftPM 对依赖包的 unsafe build flags 有限制。
//
// 消费方 import 的模块名是 `UnrarKit`（product 名 UnrarKitLocal）。
// 注意：App 链接需要 -ObjC（ObjC 类别在静态归档中默认会被裁掉）。

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
            targets: ["UnrarKit"]
        ),
    ],
    targets: [
        .target(
            name: "UnrarKit",
            path: ".",
            exclude: [
                "LICENSE"
            ],
            sources: [
                "Classes/URKArchive.mm",
                "Classes/URKFileInfo.m",
                "Classes/NSString+UnrarKit.mm",
                "Libraries/unrar/dll.cpp"
            ],
            publicHeadersPath: "Classes",
            cxxSettings: [
                .headerSearchPath("Libraries/unrar"),
                .headerSearchPath("Classes"),
                .define("RARDLL"),
                .define("UNRAR"),
                .define("_UNIX"),
                .define("_FILE_OFFSET_BITS", to: "64"),
                .define("LARGEFILE_SOURCE")
            ],
            linkerSettings: [
                .linkedLibrary("z")
            ]
        )
    ],
    // unrar 6.12 的 makefile 不指定语言标准（跟随编译器默认，现代 clang 为 gnu++14+），
    // 强制 c++11 有踩到 C++14 特性的风险，这里给到 c++14
    cxxLanguageStandard: .cxx14
)
