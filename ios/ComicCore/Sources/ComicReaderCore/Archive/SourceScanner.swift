import Foundation

// MARK: - 来源扫描与读取门面（src/main/archive/index.ts 的移植）
//
// 上层只与本文件交互：按扩展名分派适配器、过滤图片条目、自然排序、
// 读取重试、页列表缓存。页面身份 = 过滤排序后列表的下标，
// lastReadPage / bookmarks 的含义在各平台间保持一致。

/// 已注册的格式适配器（App 启动时注入 ZIP/RAR/PDF 实现）
public final class ArchiveRegistry: @unchecked Sendable {
    private var readers: [ArchiveFormat: ArchiveReader] = [:]

    public init() {}

    public func register(_ format: ArchiveFormat, _ reader: ArchiveReader) {
        readers[format] = reader
    }

    func reader(for sourcePath: String) throws -> ArchiveReader {
        guard let format = archiveFormat(sourcePath),
              let reader = readers[format] else {
            throw SourceError("不支持的文件格式（支持 ZIP、CBZ、RAR、CBR、PDF）")
        }
        return reader
    }

    public func releaseAll() {
        for reader in readers.values { reader.releaseAll() }
    }
}

/// 全局注册表（对应桌面版的模块级 zipReader / rarReader / pdfReader 单例）
public nonisolated(unsafe) var sharedArchiveRegistry = ArchiveRegistry()

public func readerFor(_ sourcePath: String) throws -> ArchiveReader {
    try sharedArchiveRegistry.reader(for: sourcePath)
}

extension ArchiveRegistry {
    /// 装配内置适配器；App 启动时调用一次（注册表默认为空，缺了这一步
    /// 所有压缩包的导入与阅读都会报「不支持的文件格式」）。
    /// 放在 Core 里做 canImport 门控，保证与各适配器的编译条件永远一致。
    public func installBuiltinReaders() {
        #if canImport(ZIPFoundation)
        register(.zip, ZipArchiveReader())
        #endif
        #if canImport(UnrarKit)
        register(.rar, RarArchiveReader())
        #endif
        #if canImport(PDFKit)
        register(.pdf, PdfArchiveReader())
        #endif
    }
}

/// 来源是否仍然可访问（书架“来源丢失”校验用）
public func sourceExists(_ sourcePath: String) -> Bool {
    FileManager.default.fileExists(atPath: sourcePath)
}

// ---------------------------------------------------------------------------
// 目录/压缩包扫描
// ---------------------------------------------------------------------------

func walkFolderImages(root: String, rel: String, out: inout [String]) throws {
    let dir = rel.isEmpty ? root : root + "/" + rel
    let fm = FileManager.default
    var children: [String]
    do {
        children = try fm.contentsOfDirectory(atPath: dir)
    } catch {
        if rel.isEmpty { throw SourceError("无法读取文件夹：\(dir)", path: dir) }
        return // 子目录读不了就跳过，不让整本失败
    }
    for name in children.sorted() {
        if name.hasPrefix(".") || name == "__MACOSX" { continue }
        let relPath = rel.isEmpty ? name : rel + "/" + name
        var isDir: ObjCBool = false
        fm.fileExists(atPath: dir + "/" + name, isDirectory: &isDir)
        if isDir.boolValue {
            try walkFolderImages(root: root, rel: relPath, out: &out)
        } else if isImagePath(name) {
            out.append(relPath)
        }
    }
}

/// 扫描来源，返回自然排序后的页面条目列表（folder 为相对路径，archive 为文件内条目名）
public func scanSource(sourceType: SourceType, sourcePath: String) throws -> [String] {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: sourcePath, isDirectory: &isDir) else {
        throw SourceError(
            sourceType == .folder
                ? "文件夹不存在，可能已被移动或删除：\(sourcePath)"
                : "文件不存在，可能已被移动或删除：\(sourcePath)",
            path: sourcePath
        )
    }

    if sourceType == .folder {
        guard isDir.boolValue else { throw SourceError("该路径不是文件夹") }
        var out: [String] = []
        try walkFolderImages(root: sourcePath, rel: "", out: &out)
        return naturalSort(out)
    }

    guard !isDir.boolValue else { throw SourceError("该路径不是文件") }
    let entries = try readerFor(sourcePath).list(sourcePath)
    return naturalSort(
        entries
            .filter { !$0.isDirectory && !isJunkEntry($0.name) && isImagePath($0.name) }
            .map(\.name)
    )
}

/// 释放某个来源占用的压缩包句柄
public func releaseSource(_ sourcePath: String) {
    guard archiveFormat(sourcePath) != nil else { return }
    try? readerFor(sourcePath).release(sourcePath)
}

/// 读取来源中的单个条目字节
public func readEntry(sourceType: SourceType, sourcePath: String, entry: String) throws -> PageBytes {
    if sourceType == .folder {
        let full = sourcePath + "/" + entry
        guard let data = FileManager.default.contents(atPath: full) else {
            throw SourceError("图片读取失败：\(entry)", path: full)
        }
        return PageBytes(data: data, mime: mimeFor(entry))
    }

    let reader = try readerFor(sourcePath)
    do {
        let data = try reader.read(sourcePath, entry: entry)
        return PageBytes(data: data, mime: mimeFor(entry))
    } catch let err as SourceError {
        throw err
    } catch {
        // 句柄可能因文件被替换而失效：丢掉缓存重试一次
        reader.release(sourcePath)
        do {
            let data = try reader.read(sourcePath, entry: entry)
            return PageBytes(data: data, mime: mimeFor(entry))
        } catch let retryErr as SourceError {
            throw retryErr
        } catch {
            throw SourceError("读取文件内页面失败，文件可能已损坏", path: sourcePath)
        }
    }
}

// ---------------------------------------------------------------------------
// 每本漫画的页面列表缓存（阅读会话内复用，打开漫画时强制刷新）
// ---------------------------------------------------------------------------

final class PageListCacheStore: @unchecked Sendable {
    private var cache: [String: [String]] = [:]
    private let lock = NSLock()

    func invalidate(_ comicId: String) {
        lock.lock(); defer { lock.unlock() }
        cache[comicId] = nil
    }

    func get(_ comicId: String) -> [String]? {
        lock.lock(); defer { lock.unlock() }
        return cache[comicId]
    }

    func set(_ comicId: String, _ pages: [String]) {
        lock.lock(); defer { lock.unlock() }
        cache[comicId] = pages
    }
}

nonisolated(unsafe) let sharedPageListCache = PageListCacheStore()

public func invalidateComic(_ comicId: String) {
    sharedPageListCache.invalidate(comicId)
}

public func getPageList(_ comic: Comic) throws -> [String] {
    if let cached = sharedPageListCache.get(comic.id) { return cached }
    let pages = try scanSource(sourceType: comic.sourceType, sourcePath: comic.sourcePath)
    sharedPageListCache.set(comic.id, pages)
    return pages
}

/// 按页码读取图片（阅读器取页的唯一入口）
public func readPage(_ comic: Comic, index: Int) throws -> PageBytes {
    let pages = try getPageList(comic)
    guard index >= 0, index < pages.count else {
        throw SourceError("页码超出范围：\(index + 1) / \(pages.count)")
    }
    return try readEntry(sourceType: comic.sourceType, sourcePath: comic.sourcePath, entry: pages[index])
}

/// 阻塞式读取的专用并发队列。ArchiveReader 是同步 API，内部用信号量
/// （AsyncBridge）等待句柄获取——绝不能在 Swift 协作线程池的线程上跑：
/// 池宽 ≈ 核数，当前页 + 预取 + 缩略图并发时线程全被信号量占满，
/// 内部的 Task 永远排不上队，表现为「偶尔有页面加载失败」。
/// 这里把同步世界挪到 GCD 线程（GCD 会为阻塞工作补线程），调用方挂起等待。
private let archiveReadQueue = DispatchQueue(
    label: "com.comicreader.archive.reads", attributes: .concurrent
)

public func readPageAsync(_ comic: Comic, index: Int) async throws -> PageBytes {
    try await withCheckedThrowingContinuation { continuation in
        archiveReadQueue.async {
            continuation.resume(with: Result { try readPage(comic, index: index) })
        }
    }
}

/// 扫描来源的异步形态（open / rescan 用）：压缩包的 list() 内部经
/// awaitBlocking 信号量等待，绝不能落在主线程或协作线程池上调用
public func scanSourceAsync(sourceType: SourceType, sourcePath: String) async throws -> [String] {
    try await withCheckedThrowingContinuation { continuation in
        archiveReadQueue.async {
            continuation.resume(with: Result {
                try scanSource(sourceType: sourceType, sourcePath: sourcePath)
            })
        }
    }
}

/// 把整段含阻塞归档操作的流程（如导入：scanSource + 封面条目读取都有
/// awaitBlocking 信号量等待）派到专用 GCD 队列执行——调用方挂起等待。
/// 这些信号量等待绝不能落在 Swift 协作线程池的线程上（池宽 ≈ 核数，
/// 被占满后全局异步工作停摆）
public func runOnArchiveQueue<T>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        archiveReadQueue.async {
            continuation.resume(with: Result { try body() })
        }
    }
}

/// 章节目录项：分章节文件夹（或压缩包内分章节目录）的漫画按首个路径段
/// 分组得到的章节
public struct ComicChapter: Equatable, Sendable {
    /// 章节名（首个路径段）；根目录散页组成的章节为空串（界面显示「正文」）
    public let title: String
    /// 章节首页在整本页面列表中的下标（页面身份 = 过滤排序后列表的下标）
    public let startPage: Int
    public let pageCount: Int

    public init(title: String, startPage: Int, pageCount: Int) {
        self.title = title
        self.startPage = startPage
        self.pageCount = pageCount
    }
}

/// 从自然排序后的页面条目推导章节目录。
/// 规则：条目含 "/" 时首个路径段为章节名；不含的归入开头的无名章节。
/// 按页面列表中的连续同名段切分（同名段不连续时成为两个章节）。
/// 章节数不足 2 时返回空（没有目录可言）。
public func deriveChapters(from pages: [String]) -> [ComicChapter] {
    guard pages.contains(where: { $0.contains("/") }) else { return [] }

    var out: [ComicChapter] = []
    var currentTitle: String?
    var count = 0

    func flush(endedAt index: Int) {
        if let title = currentTitle, count > 0 {
            out.append(ComicChapter(title: title, startPage: index - count, pageCount: count))
        }
    }

    for (i, entry) in pages.enumerated() {
        let title: String
        if let sep = entry.firstIndex(of: "/") {
            title = String(entry[..<sep])
        } else {
            title = ""
        }
        if title != currentTitle {
            flush(endedAt: i)
            currentTitle = title
            count = 0
        }
        count += 1
    }
    flush(endedAt: pages.count)

    return out.count >= 2 ? out : []
}

/// 去掉「 (2)」式去重后缀（导入落盘重名时文件选择器 / 局域网都会自动追加；
/// 判断「同名并入既有书目」时用它还原原始名字）
public func stripDedupSuffix(_ name: String) -> String {
    var s = name
    while let r = s.range(of: #" \([0-9]+\)$"#, options: .regularExpression) {
        s = String(s[..<r.lowerBound])
    }
    return s
}

/// 页列表变化（同名并入新章节）后把旧页码映射到新页码：优先按条目名找回
/// 同一页（新章节插在前面时页码整体平移）；条目消失则按比例近似，最后夹进范围
public func remapPage(_ index: Int, old: [String], new: [String]) -> Int {
    guard !new.isEmpty else { return 0 }
    guard index >= 0, index < old.count else {
        return min(max(0, index), new.count - 1)
    }
    if let to = new.firstIndex(of: old[index]) {
        return to
    }
    let ratio = Double(index) / Double(old.count)
    return min(Int((ratio * Double(new.count)).rounded()), new.count - 1)
}

/// 解压来源压缩包到目标目录（章节并入用）。
/// 返回写出的文件数；仅支持 ZIP/CBZ（RAR/PDF 不参与同名并入）。
/// canImport 门控与 installBuiltinReaders 同理：Windows 本地没有 ZIPFoundation
@discardableResult
public func extractSourceArchive(sourcePath: String, toDirectory dir: String) throws -> Int {
    #if canImport(ZIPFoundation)
    guard archiveFormat(sourcePath) == .zip else {
        throw SourceError("仅支持 ZIP/CBZ 的自动并入", path: sourcePath)
    }
    guard let zip = try readerFor(sourcePath) as? ZipArchiveReader else {
        throw SourceError("压缩包适配器不支持解压并入", path: sourcePath)
    }
    return try zip.extractAll(sourcePath, toDirectory: dir)
    #else
    throw SourceError("此平台不支持解压并入", path: sourcePath)
    #endif
}

/// 释放全部打开的压缩包句柄（进入后台时调用，对应桌面版的 before-quit）
public func closeAllSources() {
    sharedArchiveRegistry.releaseAll()
}
