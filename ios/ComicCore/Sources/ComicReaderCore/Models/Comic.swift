import Foundation

// MARK: - 书架中的一本漫画（src/shared/types.ts Comic 的移植）
//
// 字段名与 library.json 完全一致，保证桌面版备份与 iOS 互通。
// 反序列化对所有可缺省字段用 decodeIfPresent + 默认值，
// 对应桌面版 sanitizeComics 的兜底行为。

/// 双页配对偏移：1 = 封面单独占屏；0 = 从第一页起两两成对
public typealias PageOffset = Int

/// 单本漫画的阅读偏好（全部可选，缺省回退全局设置）
public struct ComicReaderPrefs: Codable, Equatable, Sendable {
    public var mode: ReadingMode?
    public var zoom: ZoomMode?
    /// 在缩放模式基础上的倍率，1 = 100%
    public var zoomScale: Double?
    public var direction: ReadingDirection?
    /// 双页配对偏移（v4 新增），缺省时取全局 doubleCoverSingle
    public var pageOffset: PageOffset?
    /// 自动裁掉扫描留下的白边（v4 新增），缺省时取全局 autoCrop
    public var autoCrop: Bool?
    /// 滚动模式下的自动翻页改为匀速向下平滑滚动（v5 新增，条漫专用），缺省为按屏翻
    public var autoScroll: Bool?

    public init(
        mode: ReadingMode? = nil,
        zoom: ZoomMode? = nil,
        zoomScale: Double? = nil,
        direction: ReadingDirection? = nil,
        pageOffset: PageOffset? = nil,
        autoCrop: Bool? = nil,
        autoScroll: Bool? = nil
    ) {
        self.mode = mode
        self.zoom = zoom
        self.zoomScale = zoomScale
        self.direction = direction
        self.pageOffset = pageOffset
        self.autoCrop = autoCrop
        self.autoScroll = autoScroll
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(ReadingMode.self, forKey: .mode)
        zoom = try c.decodeIfPresent(ZoomMode.self, forKey: .zoom)
        zoomScale = try c.decodeIfPresent(Double.self, forKey: .zoomScale)
        direction = try c.decodeIfPresent(ReadingDirection.self, forKey: .direction)
        pageOffset = try c.decodeIfPresent(PageOffset.self, forKey: .pageOffset)
        autoCrop = try c.decodeIfPresent(Bool.self, forKey: .autoCrop)
        autoScroll = try c.decodeIfPresent(Bool.self, forKey: .autoScroll)
    }
}

/// 书架中的一本漫画
public struct Comic: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var sourceType: SourceType
    /// 原始文件/文件夹的绝对路径，删除条目时不会删除它
    public var sourcePath: String
    public var pageCount: Int
    /// 封面文件名（位于 covers 目录下），生成失败时为 nil
    public var coverFile: String?
    public var addedAt: Double
    public var lastReadAt: Double?
    /// 0 起始的页码
    public var lastReadPage: Int
    public var reader: ComicReaderPrefs
    /// 所属分类 id 列表（v3 新增，一本漫画可属于多个分类）
    public var categoryIds: [String]
    /// 书签页码，0 起始、升序去重（v4 新增，属于「书签」扩展功能）
    public var bookmarks: [Int]
    /// 类型标签（v5 新增），nil = 未打标签
    public var style: ComicStyle?

    public init(
        id: String,
        title: String,
        sourceType: SourceType,
        sourcePath: String,
        pageCount: Int,
        coverFile: String? = nil,
        addedAt: Double,
        lastReadAt: Double? = nil,
        lastReadPage: Int = 0,
        reader: ComicReaderPrefs = ComicReaderPrefs(),
        categoryIds: [String] = [],
        bookmarks: [Int] = [],
        style: ComicStyle? = nil
    ) {
        self.id = id
        self.title = title
        self.sourceType = sourceType
        self.sourcePath = sourcePath
        self.pageCount = pageCount
        self.coverFile = coverFile
        self.addedAt = addedAt
        self.lastReadAt = lastReadAt
        self.lastReadPage = lastReadPage
        self.reader = reader
        self.categoryIds = categoryIds
        self.bookmarks = bookmarks
        self.style = style
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        sourceType = try c.decodeIfPresent(SourceType.self, forKey: .sourceType) ?? .archive
        sourcePath = try c.decode(String.self, forKey: .sourcePath)
        pageCount = try c.decodeIfPresent(Int.self, forKey: .pageCount) ?? 0
        coverFile = try c.decodeIfPresent(String.self, forKey: .coverFile)
        addedAt = try c.decodeIfPresent(Double.self, forKey: .addedAt) ?? 0
        lastReadAt = try c.decodeIfPresent(Double.self, forKey: .lastReadAt)
        lastReadPage = try c.decodeIfPresent(Int.self, forKey: .lastReadPage) ?? 0
        reader = try c.decodeIfPresent(ComicReaderPrefs.self, forKey: .reader) ?? ComicReaderPrefs()
        categoryIds = try c.decodeIfPresent([String].self, forKey: .categoryIds) ?? []
        bookmarks = try c.decodeIfPresent([Int].self, forKey: .bookmarks) ?? []
        style = try c.decodeIfPresent(ComicStyle.self, forKey: .style)
    }
}

/// 自定义分类（v3 新增，属于「自定义分类」扩展功能）
public struct Category: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// 预设调色板中的颜色，形如 #rrggbb
    public var color: String
    public var createdAt: Double

    public init(id: String, name: String, color: String, createdAt: Double) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = createdAt
    }
}

// MARK: - 操作结果类型（src/shared/types.ts 的移植）

public struct CategoryMutationResult: Sendable {
    public var ok: Bool
    public var category: Category?
    public var error: String?

    public init(ok: Bool, category: Category? = nil, error: String? = nil) {
        self.ok = ok
        self.category = category
        self.error = error
    }
}

public struct CategoryPatch: Sendable {
    public var name: String?
    public var color: String?

    public init(name: String? = nil, color: String? = nil) {
        self.name = name
        self.color = color
    }
}

public enum ImportStatus: String, Sendable {
    case imported
    case skipped
    case failed
}

public struct ImportResult: Sendable {
    public var path: String
    public var status: ImportStatus
    public var comic: Comic?
    public var reason: String?

    public init(path: String, status: ImportStatus, comic: Comic? = nil, reason: String? = nil) {
        self.path = path
        self.status = status
        self.comic = comic
        self.reason = reason
    }
}

public struct OpenComicResult: Sendable {
    public var ok: Bool
    public var comic: Comic?
    public var pageCount: Int?
    public var error: String?

    public init(ok: Bool, comic: Comic? = nil, pageCount: Int? = nil, error: String? = nil) {
        self.ok = ok
        self.comic = comic
        self.pageCount = pageCount
        self.error = error
    }
}

public struct ProgressPatch: Sendable {
    public var lastReadPage: Int?
    public var reader: ComicReaderPrefs?

    public init(lastReadPage: Int? = nil, reader: ComicReaderPrefs? = nil) {
        self.lastReadPage = lastReadPage
        self.reader = reader
    }
}

public struct SourceCheck: Sendable {
    public var id: String
    public var missing: Bool

    public init(id: String, missing: Bool) {
        self.id = id
        self.missing = missing
    }
}

public struct RenameResult: Sendable {
    public var ok: Bool
    public var comic: Comic?
    public var error: String?

    public init(ok: Bool, comic: Comic? = nil, error: String? = nil) {
        self.ok = ok
        self.comic = comic
        self.error = error
    }
}

public struct BatchRescanResult: Sendable {
    public struct Failure: Sendable {
        public var id: String
        public var title: String
        public var error: String

        public init(id: String, title: String, error: String) {
            self.id = id
            self.title = title
            self.error = error
        }
    }

    public var updated: [Comic]
    public var failed: [Failure]

    public init(updated: [Comic], failed: [Failure]) {
        self.updated = updated
        self.failed = failed
    }
}

public struct RelocateResult: Sendable {
    /// 用户取消了目录选择
    public var canceled: Bool
    /// 选中的新根目录
    public var root: String?
    /// 成功改绑的记录
    public var relocated: [Comic]
    /// 在新根目录下没找到对应文件的数量
    public var unmatched: Int
    public var error: String?

    public init(
        canceled: Bool,
        root: String? = nil,
        relocated: [Comic] = [],
        unmatched: Int = 0,
        error: String? = nil
    ) {
        self.canceled = canceled
        self.root = root
        self.relocated = relocated
        self.unmatched = unmatched
        self.error = error
    }
}

public struct BackupResult: Sendable {
    public var canceled: Bool
    public var ok: Bool
    /// 备份目录的完整路径
    public var path: String?
    public var comics: Int?
    public var covers: Int?
    public var error: String?

    public init(
        canceled: Bool, ok: Bool, path: String? = nil,
        comics: Int? = nil, covers: Int? = nil, error: String? = nil
    ) {
        self.canceled = canceled
        self.ok = ok
        self.path = path
        self.comics = comics
        self.covers = covers
        self.error = error
    }
}

public struct RestoreResult: Sendable {
    public var canceled: Bool
    public var ok: Bool
    public var mode: RestoreMode?
    public var imported: Int?
    public var skipped: Int?
    public var error: String?

    public init(
        canceled: Bool, ok: Bool, mode: RestoreMode? = nil,
        imported: Int? = nil, skipped: Int? = nil, error: String? = nil
    ) {
        self.canceled = canceled
        self.ok = ok
        self.mode = mode
        self.imported = imported
        self.skipped = skipped
        self.error = error
    }
}

public struct ScanRootsResult: Sendable {
    /// 扫描过的根目录数量
    public var roots: Int
    /// 自动上架的新漫画
    public var added: [Comic]
    /// 读不了的根目录
    public var unreadable: [String]

    public init(roots: Int, added: [Comic], unreadable: [String]) {
        self.roots = roots
        self.added = added
        self.unreadable = unreadable
    }
}
