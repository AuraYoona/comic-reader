import Foundation

// MARK: - 导入器（src/main/importer.ts 的移植）
//
// 桌面版在主进程完成「判类型 → 查重 → 扫页 → 生成封面 → 落库」；
// iOS 把同一套流程放进 ComicReaderCore，供文件选择器与库根目录增量扫描复用。
//
// 与桌面版的有意差异（其余逐行对齐）：
//   - 封面一步到位：iOS 上 ImageIO 直接生成 .jpg（桌面版是「原图直存 + 渲染进程
//     二次压缩」两阶段），生成器经 CoverMaking 注入，测试可替换；
//   - 没有 Node 的 path.resolve，用 standardizedFileURL 做同样的路径归一化；
//   - expandBatchRoot 额外跳过 __MACOSX（iOS 用户从 macOS 同步的目录常带资源叉，
//     桌面版只在 walkFolderImages 里过滤它）。

/// 批量导入进度（current 从 1 起）
public struct ImportProgressInfo: Sendable {
    public var current: Int
    public var total: Int
    public var path: String

    public init(current: Int, total: Int, path: String) {
        self.current = current
        self.total = total
        self.path = path
    }
}

/// 封面生成注入点（ImageIO 实现在别的文件；测试注入假的）
public protocol CoverMaking: Sendable {
    /// 从第一页字节生成封面 JPEG；失败返回 nil
    func makeCover(fromPageData data: Data) -> Data?
}

public final class Importer: @unchecked Sendable {
    private let db: LibraryDatabase
    private let coversDir: String
    private let coverFactory: (any CoverMaking)?
    private let now: @Sendable () -> Double

    public init(
        db: LibraryDatabase,
        coversDir: String,
        coverFactory: (any CoverMaking)? = nil,
        now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 * 1000 }
    ) {
        self.db = db
        self.coversDir = coversDir
        self.coverFactory = coverFactory
        self.now = now
    }

    // MARK: 批量导入

    /// 桌面版 importPaths：逐个导入，单项失败不影响其余；progress 每项一次。
    /// 与桌面版相同，回调发生在处理该项「之前」（current = 正在处理的第几项），
    /// 跳过与失败的项同样会回调。
    @discardableResult
    public func importPaths(
        _ paths: [String],
        progress: (@Sendable (ImportProgressInfo) -> Void)? = nil
    ) -> [ImportResult] {
        var results: [ImportResult] = []
        var seenInBatch = Set<String>()
        for (index, path) in paths.enumerated() {
            progress?(ImportProgressInfo(current: index + 1, total: paths.count, path: path))
            results.append(importOne(path, seenInBatch: &seenInBatch))
        }
        return results
    }

    /// 导入单项；路径不存在 / 类型不支持 / 0 页都只失败这一项，不抛出
    private func importOne(_ rawPath: String, seenInBatch: inout Set<String>) -> ImportResult {
        let sourcePath = resolvePath(rawPath)
        do {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: sourcePath, isDirectory: &isDir) else {
                return failed(sourcePath, "路径不存在")
            }

            let sourceType: SourceType
            if isDir.boolValue {
                sourceType = .folder
            } else if isArchivePath(sourcePath) {
                sourceType = .archive
            } else {
                return failed(
                    sourcePath,
                    "不支持的文件类型（支持文件夹、ZIP / CBZ / RAR / CBR 与 PDF）"
                )
            }

            let norm = normalizeForCompare(sourcePath)
            if seenInBatch.contains(norm) {
                return ImportResult(path: sourcePath, status: .skipped, reason: "重复选择")
            }
            seenInBatch.insert(norm)

            let existing = db.listComics().first { normalizeForCompare($0.sourcePath) == norm }
            if let existing {
                return ImportResult(
                    path: sourcePath, status: .skipped, comic: existing, reason: "已在书架中"
                )
            }

            let pages = try scanSource(sourceType: sourceType, sourcePath: sourcePath)
            if pages.isEmpty {
                return failed(
                    sourcePath,
                    sourceType == .folder ? "文件夹中没有找到图片" : "文件中没有找到可阅读的页面"
                )
            }

            let id = UUID().uuidString.lowercased()
            let base = URL(fileURLWithPath: sourcePath).lastPathComponent
            let title = sourceType == .archive ? stripArchiveExt(base) : base
            let coverFile = generateCover(
                id: id, sourceType: sourceType, sourcePath: sourcePath, firstPage: pages[0]
            )

            let comic = Comic(
                id: id,
                title: title,
                sourceType: sourceType,
                sourcePath: sourcePath,
                pageCount: pages.count,
                coverFile: coverFile,
                addedAt: now(),
                lastReadAt: nil,
                lastReadPage: 0,
                reader: ComicReaderPrefs(),
                // 新导入的漫画不属于任何分类，也没有书签和类型标签
                categoryIds: [],
                bookmarks: [],
                style: nil
            )
            db.upsertComic(comic)
            return ImportResult(path: sourcePath, status: .imported, comic: comic)
        } catch {
            return failed(sourcePath, importErrorMessage(error))
        }
    }

    // MARK: 封面

    /// 生成封面文件并返回文件名；任何一步失败都返回 nil（封面缺失不阻塞导入）。
    /// iOS 单阶段：读第一页字节 → makeCover → 写 coversDir/<id>.jpg，文件名恒为 .jpg。
    private func generateCover(
        id: String, sourceType: SourceType, sourcePath: String, firstPage: String
    ) -> String? {
        guard let coverFactory else { return nil }
        do {
            let bytes = try readEntry(sourceType: sourceType, sourcePath: sourcePath, entry: firstPage)
            guard let jpeg = coverFactory.makeCover(fromPageData: bytes.data) else { return nil }
            let fileName = "\(id)\(COVER_THUMB_EXT)"
            try FileManager.default.createDirectory(atPath: coversDir, withIntermediateDirectories: true)
            try jpeg.write(to: URL(fileURLWithPath: coversDir + "/" + fileName))
            return fileName
        } catch {
            return nil
        }
    }

    // MARK: 库根目录

    /// 桌面版 expandBatchRoot：把「漫画库根目录」展开成待导入项 ——
    /// 每个子文件夹、压缩包（含 PDF）算一本；只列一层，不递归。
    /// 跳过 "." 开头与 __MACOSX；根目录本身读不了返回 nil。
    public func expandBatchRoot(_ root: String) -> [String]? {
        let resolvedRoot = resolvePath(root)
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: resolvedRoot) else {
            return nil
        }
        var targets: [String] = []
        for name in names.sorted() {
            if name.hasPrefix(".") || name == "__MACOSX" { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: resolvedRoot + "/" + name, isDirectory: &isDir) else { continue }
            if isDir.boolValue || isArchivePath(name) {
                targets.append(resolvedRoot + "/" + name)
            }
        }
        return targets
    }

    /// 桌面版 findUnimportedInRoot：返回根下第一层里尚未在书架的项。
    /// 根读不了时桌面版返回 null，这里收窄成空数组（调用方可先用 expandBatchRoot 区分）。
    public func findUnimported(inRoot root: String) -> [String] {
        guard let targets = expandBatchRoot(root) else { return [] }
        return unimportedSubset(of: targets)
    }

    /// 桌面版 scanLibraryRoots：依次扫描 settings.libraryRoots，把新出现的项自动上架。
    /// roots 与桌面版 r.roots 一致：settings 里记录的根总数（含读不了的）。
    public func scanLibraryRoots() -> ScanRootsResult {
        let roots = db.getSettings().libraryRoots
        var added: [Comic] = []
        var unreadable: [String] = []
        for root in roots {
            guard let targets = expandBatchRoot(root) else {
                unreadable.append(root)
                continue
            }
            let pending = unimportedSubset(of: targets)
            if pending.isEmpty { continue }
            for result in importPaths(pending) where result.status == .imported {
                if let comic = result.comic { added.append(comic) }
            }
        }
        return ScanRootsResult(roots: roots.count, added: added, unreadable: unreadable)
    }

    private func unimportedSubset(of targets: [String]) -> [String] {
        let known = Set(db.listComics().map { normalizeForCompare($0.sourcePath) })
        return targets.filter { !known.contains(normalizeForCompare($0)) }
    }

    // MARK: 私有工具

    private func failed(_ path: String, _ reason: String) -> ImportResult {
        ImportResult(path: path, status: .failed, reason: reason)
    }

    /// 桌面版 path.resolve 的移植：归一化绝对路径（去掉 ./、..、重复与末尾斜杠）。
    /// 不做符号链接解析 —— path.resolve 也不做。
    private func resolvePath(_ rawPath: String) -> String {
        var path = URL(fileURLWithPath: rawPath).standardizedFileURL.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    /// 桌面版 `err instanceof SourceError ? err.message : `导入失败：${err.message}``
    private func importErrorMessage(_ error: Error) -> String {
        if let source = error as? SourceError { return source.message }
        return "导入失败：\((error as NSError).localizedDescription)"
    }
}
