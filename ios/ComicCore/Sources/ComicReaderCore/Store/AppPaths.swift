import Foundation

// MARK: - 应用路径（app.getPath('userData') 的移植）
//
// 桌面版：library.json / covers/ 都在 userData 下。
// iOS：Application Support/ComicReader/（应用私有、随备份迁移、不在 Files 中可见）；
// 用户内容统一放 Documents/Comics/，两者职责分开。
// 测试注入临时目录。

public struct AppPaths: Sendable {
    /// 应用私有数据目录（library.json、covers/）
    public let supportDir: String
    /// 用户可见的漫画目录（Documents/Comics）
    public let comicsDir: String

    public init(supportDir: String, comicsDir: String) {
        self.supportDir = supportDir
        self.comicsDir = comicsDir
    }

    public var libraryPath: String { supportDir + "/library.json" }
    public var coversDir: String { supportDir + "/covers" }
    /// 每本漫画的页元数据 sidecar 目录（页宽高比 / 页内进度）
    public var pageMetaDir: String { supportDir + "/page-meta" }

    /// 生产环境路径（iOS）
    public static func live() -> AppPaths {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ComicReader", isDirectory: true)
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Comics", isDirectory: true)
        return AppPaths(supportDir: base.path, comicsDir: docs.path)
    }

    /// 确保目录存在
    public func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: coversDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: pageMetaDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: comicsDir, withIntermediateDirectories: true)
    }
}
