// swift-tools-version:5.3
// vendored UnrarKit：官方 UnRAR 6.12 源码（RAR4 + RAR5 完整支持）。
//
// 源文件清单严格按 unrar makefile 的库构建目标（OBJECTS + LIB_OBJ）：
//   OBJECTS = rar.o strlist.o … ui.o
//   LIB_OBJ = filestr.o scantree.o dll.o qopen.o
// 只有 dll.cpp 是不够的 —— 它依赖整个引擎（ErrHandler / MergeArchive /
// CharToWide…），CI 链接期以未定义符号形式暴露过这一点。
// 控制台工具专属的 unrar.cpp（含 main）与 recvol/rs 不在库构建内，排除。
//
// 其他设计说明：
//   - 单一 target：四个包装源（URKArchive.mm / URKFileInfo.m /
//     NSString+UnrarKit.mm / dll.cpp）+ 全部引擎源编译进一个归档。多 target
//     曾在 CI 触发链接期问题，合并后链接面上只有一个归档。
//   - publicHeadersPath（Classes/）只允许平铺头文件：raros.hpp 与 dll.hpp
//     是从 Libraries/unrar/ 镜像进来的（公共头依赖它们，而 SPM 不会把
//     unrar 的 include 目录暴露给 clang 模块构建）。
//   - 不用 unsafeFlags：SwiftPM 对依赖包的 unsafe build flags 有限制。
//
// 消费方 import 的模块名是 `UnrarKit`（product 名 UnrarKitLocal）。
// 注意：App 链接需要 -ObjC（ObjC 类别在静态归档中默认会被裁掉）。

import PackageDescription

// unrar makefile: OBJECTS + LIB_OBJ（去掉 Windows 专属与工具专属）
let unrarEngineSources: [String] = [
    "archive.cpp", "arcread.cpp", "blake2s.cpp", "cmddata.cpp", "consio.cpp",
    "crc.cpp", "crypt.cpp", "encname.cpp", "errhnd.cpp", "extinfo.cpp",
    "extract.cpp", "file.cpp", "filefn.cpp", "filcreat.cpp", "filestr.cpp",
    "find.cpp", "getbits.cpp", "global.cpp", "hash.cpp", "headers.cpp",
    "list.cpp", "match.cpp", "options.cpp", "pathfn.cpp", "qopen.cpp",
    "rar.cpp", "rarvm.cpp", "rawread.cpp", "rdwrfn.cpp", "resource.cpp",
    "rijndael.cpp", "rs16.cpp", "scantree.cpp", "secpassword.cpp", "sha1.cpp",
    "sha256.cpp", "smallfn.cpp", "strfn.cpp", "strlist.cpp", "system.cpp",
    "threadpool.cpp", "timefn.cpp", "ui.cpp", "unicode.cpp", "unpack.cpp",
    "volume.cpp"
].map { "Libraries/unrar/\($0)" }

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
            ] + unrarEngineSources,
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
