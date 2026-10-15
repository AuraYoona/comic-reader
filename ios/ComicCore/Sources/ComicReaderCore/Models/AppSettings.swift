import Foundation

// MARK: - 全局设置（src/shared/types.ts AppSettings 的移植）
//
// 字段名与 library.json settings 完全一致。
// 桌面专属键（autoCheckUpdates / mouseSideButtons）保留在 schema 里以兼容备份，
// iOS 上对应入口隐藏、无实际作用。

public struct AppSettings: Codable, Equatable, Sendable {
    public var theme: ThemeMode
    public var readingDirection: ReadingDirection
    public var defaultMode: ReadingMode
    public var defaultZoom: ZoomMode
    /// 启动时自动打开上次阅读的漫画
    public var openLastOnStartup: Bool
    public var lastOpenedComicId: String?
    /// 书架卡片大小（v2 新增）
    public var cardSize: CardSize
    /// 扩展功能开关（v3 新增），关闭只隐藏入口，不删除任何数据
    public var extensions: ExtensionFlags
    /// 启动时自动检查更新（仅桌面版生效；iOS 保留字段以兼容备份）
    public var autoCheckUpdates: Bool

    // ---- v4 新增 ----
    /// 双页模式默认让第一页（封面）单独占屏
    public var doubleCoverSingle: Bool
    /// 双页模式下把横向跨页图铺满整屏，不塞进半个视口
    public var widePageSpread: Bool
    /// 阅读器亮度滤镜，1 = 原始亮度
    public var brightness: Double
    /// 自动翻页间隔（秒）
    public var autoTurnSeconds: Int
    /// 鼠标侧键翻页（仅桌面版生效；iOS 保留字段以兼容备份）
    public var mouseSideButtons: Bool
    /// 默认自动裁掉扫描白边
    public var autoCrop: Bool
    /// 漫画库根目录，批量导入时自动记录
    public var libraryRoots: [String]
    /// 启动时扫描库根目录，把新增的漫画自动上架
    public var autoScanRoots: Bool

    // ---- v5 新增 ----
    /// 条漫平滑自动滚动的速度（像素 / 秒）
    public var autoScrollSpeed: Double

    public init(
        theme: ThemeMode = .system,
        readingDirection: ReadingDirection = .ltr,
        defaultMode: ReadingMode = .single,
        defaultZoom: ZoomMode = .fitWidth,
        openLastOnStartup: Bool = false,
        lastOpenedComicId: String? = nil,
        cardSize: CardSize = .medium,
        extensions: ExtensionFlags = ExtensionFlags(),
        autoCheckUpdates: Bool = true,
        doubleCoverSingle: Bool = true,
        widePageSpread: Bool = true,
        brightness: Double = 1,
        autoTurnSeconds: Int = 6,
        mouseSideButtons: Bool = true,
        autoCrop: Bool = false,
        libraryRoots: [String] = [],
        autoScanRoots: Bool = true,
        autoScrollSpeed: Double = 80
    ) {
        self.theme = theme
        self.readingDirection = readingDirection
        self.defaultMode = defaultMode
        self.defaultZoom = defaultZoom
        self.openLastOnStartup = openLastOnStartup
        self.lastOpenedComicId = lastOpenedComicId
        self.cardSize = cardSize
        self.extensions = extensions
        self.autoCheckUpdates = autoCheckUpdates
        self.doubleCoverSingle = doubleCoverSingle
        self.widePageSpread = widePageSpread
        self.brightness = brightness
        self.autoTurnSeconds = autoTurnSeconds
        self.mouseSideButtons = mouseSideButtons
        self.autoCrop = autoCrop
        self.libraryRoots = libraryRoots
        self.autoScanRoots = autoScanRoots
        self.autoScrollSpeed = autoScrollSpeed
    }

    public static let defaults = AppSettings()
}

/// 扩展功能开关（Record<ExtensionId, boolean> 的移植）
public struct ExtensionFlags: Codable, Equatable, Sendable {
    public var categories: Bool
    public var bookmarks: Bool

    public init(categories: Bool = false, bookmarks: Bool = false) {
        self.categories = categories
        self.bookmarks = bookmarks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categories = try c.decodeIfPresent(Bool.self, forKey: .categories) ?? false
        bookmarks = try c.decodeIfPresent(Bool.self, forKey: .bookmarks) ?? false
    }
}
