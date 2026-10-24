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

/// 释放全部打开的压缩包句柄（进入后台时调用，对应桌面版的 before-quit）
public func closeAllSources() {
    sharedArchiveRegistry.releaseAll()
}
