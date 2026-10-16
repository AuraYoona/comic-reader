import Foundation
import ComicReaderCore

// MARK: - 书架状态（src/renderer/src/store/library.ts + Bookshelf.tsx 的移植）
//
// 搜索 150ms 防抖、来源校验 8s 节流、排序/筛选哨兵值、多选锚点、
// 批量操作（分类 / 类型 / 重扫 / 移除）——语义与桌面版对齐。

@MainActor
final class ShelfStore: ObservableObject {
    /// 未分类哨兵（对齐 library.ts UNCATEGORIZED_ID）
    static let uncategorizedId = "@uncategorized"
    /// 未标记类型哨兵（对齐 library.ts UNSTYLED_ID）
    static let unstyledId = "@unstyled"
    /// 来源存在性校验节流（对齐 library.ts VERIFY_THROTTLE_MS = 8000）
    static let verifyThrottleMs: Double = 8000
    /// 搜索防抖（对齐 TopBar.tsx SEARCH_DEBOUNCE_MS = 150）
    static let searchDebounceMs = 150

    struct ImportBusy: Equatable {
        var active = false
        var label = ""
        var current = 0
        var total = 0
        var path = ""

        static let idle = ImportBusy()
    }

    @Published private(set) var comics: [Comic] = []
    @Published private(set) var loading = true
    @Published private(set) var importing = ImportBusy.idle
    /// 批量操作进行中（重扫等；禁用相关按钮）
    @Published private(set) var busy = false
    @Published private(set) var missingIds: Set<String> = []
    @Published private(set) var categories: [Category] = []

    /// 搜索输入（立即回显）；实际筛选用的 query 有 150ms 防抖
    @Published var searchText = "" {
        didSet { debounceQuery() }
    }
    @Published private(set) var query = ""
    @Published var sortKey: SortKey = .lastReadAt
    /// nil = 全部；uncategorizedId = 未分类；否则为分类 id（分类扩展关闭时该筛选不生效）
    @Published var categoryFilter: String?
    /// nil = 全部；unstyledId = 未标记；否则为 ComicStyle.rawValue
    @Published var styleFilter: String?
    @Published var selectedIds: Set<String> = []
    @Published var anchorId: String?

    private let db: LibraryDatabase
    private let settings: SettingsStore
    private let importer: Importer
    private let covers: CoverStore
    private let toasts: ToastCenter
    private let now: @Sendable () -> Double

    private var queryTask: Task<Void, Never>?
    private var lastVerifyAt: Double = -.infinity

    init(
        db: LibraryDatabase,
        settings: SettingsStore,
        importer: Importer,
        covers: CoverStore,
        toasts: ToastCenter,
        now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 * 1000 }
    ) {
        self.db = db
        self.settings = settings
        self.importer = importer
        self.covers = covers
        self.toasts = toasts
        self.now = now
    }

    // MARK: 加载 / 来源校验

    func load() {
        loading = true
        comics = db.listComics()
        categories = db.listCategories()
        loading = false
        verifySources(force: true)
    }

    /// 来源存在性校验（8s 节流；后台批量 stat）
    func verifySources(force: Bool = false) {
        let t = now()
        if !force, t - lastVerifyAt < Self.verifyThrottleMs { return }
        lastVerifyAt = t
        let snapshot = comics
        Task { [weak self] in
            let missing: Set<String> = await Task.detached(priority: .utility) {
                var out = Set<String>()
                for comic in snapshot where !sourceExists(comic.sourcePath) {
                    out.insert(comic.id)
                }
                return out
            }.value
            self?.missingIds = missing
        }
    }

    func invalidateMissing(id: String) {
        missingIds.remove(id)
    }

    // MARK: 筛选 / 排序

    /// 当前可见列表（筛选 + 排序）
    var visible: [Comic] {
        var list = comics

        if settings.extensions.categories, let filter = categoryFilter {
            if filter == Self.uncategorizedId {
                list = list.filter { $0.categoryIds.isEmpty }
            } else {
                list = list.filter { $0.categoryIds.contains(filter) }
            }
        }

        if let filter = styleFilter {
            if filter == Self.unstyledId {
                list = list.filter { $0.style == nil }
            } else {
                list = list.filter { $0.style?.rawValue == filter }
            }
        }

        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter { $0.title.lowercased().contains(q) }
        }

        switch sortKey {
        case .title:
            // 相等键保持插入顺序（naturalCompare 的稳定版本已在 Core 提供）
            let titles = list.map(\.title)
            let order = stableTitleOrder(titles)
            return order.map { list[$0] }
        case .addedAt:
            return list.sorted { $0.addedAt > $1.addedAt }
        case .lastReadAt:
            return list.sorted {
                ($0.lastReadAt ?? 0, $0.addedAt) > ($1.lastReadAt ?? 0, $1.addedAt)
            }
        }
    }

    /// 标题排序的下标顺序（自然排序 + 相等保序）
    private func stableTitleOrder(_ titles: [String]) -> [Int] {
        let indexed = titles.enumerated().map { (index: $0.offset, title: $0.element) }
        return indexed.sorted { a, b in
            let c = naturalCompare(a.title, b.title)
            return c < 0 || (c == 0 && a.index < b.index)
        }.map(\.index)
    }

    private func debounceQuery() {
        queryTask?.cancel()
        let text = searchText
        queryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.searchDebounceMs) * 1_000_000)
            guard !Task.isCancelled else { return }
            self?.query = text
        }
    }

    // MARK: 导入

    /// 导入一批沙盒内路径（文档选择器复制进来之后调用）；返回逐项结果
    @discardableResult
    func importPaths(_ paths: [String]) async -> [ImportResult] {
        guard !importing.active, !paths.isEmpty else { return [] }
        importing = ImportBusy(active: true, label: "正在导入", current: 0, total: paths.count, path: "")

        let importer = self.importer
        let results: [ImportResult] = await Task.detached(priority: .userInitiated) {
            importer.importPaths(paths) { info in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.importing.current = info.current
                    self.importing.path = (info.path as NSString).lastPathComponent
                }
            }
        }.value

        importing = .idle
        comics = db.listComics()
        summarizeImport(results)
        return results
    }

    /// 批量导入：一个根目录下每个子文件夹 / 压缩包各算一本（对齐 expandBatchRoot）
    func importBatchRoot(_ root: String) async {
        let items = importer.expandBatchRoot(root)
        guard let items, !items.isEmpty else {
            toasts.show(.error, "这个目录里没有可导入的漫画")
            return
        }
        _ = db.addLibraryRoot(root)
        await importPaths(items)
    }

    /// 启动 / 手动扫描库目录：新增的漫画自动上架
    func scanRoots(silent: Bool = false) async {
        let importer = self.importer
        let result: ScanRootsResult = await Task.detached(priority: .utility) {
            importer.scanLibraryRoots()
        }.value

        comics = db.listComics()
        if !result.added.isEmpty {
            toasts.show(.success, "新上架 \(result.added.count) 本")
        } else if !silent {
            if result.roots == 0 {
                toasts.show(.info, "还没有库目录，先批量导入一个目录吧")
            } else {
                toasts.show(.info, "库目录里没有新漫画")
            }
        }
        if !result.unreadable.isEmpty {
            toasts.show(.error, "有 \(result.unreadable.count) 个库目录读不了")
        }
    }

    private func summarizeImport(_ results: [ImportResult]) {
        let imported = results.filter { $0.status == .imported }.count
        let skipped = results.filter { $0.status == .skipped }.count
        let failed = results.filter { $0.status == .failed }

        if imported > 0 {
            toasts.show(.success, "已导入 \(imported) 本")
        }
        if skipped > 0 {
            toasts.show(.info, "跳过 \(skipped) 本（已在书架或重复选择）")
        }
        // 失败原因最多提示 3 条（对齐 library.ts 103-121），其余合并展示
        for item in failed.prefix(3) {
            toasts.show(.error, item.reason ?? "导入失败")
        }
        if failed.count > 3 {
            toasts.show(.error, "另有 \(failed.count - 3) 本导入失败")
        }
    }

    // MARK: 单本操作

    func remove(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        // 先取封面文件名（记录删掉后就找不到了）
        let coverFiles = comics.filter { ids.contains($0.id) }.map(\.coverFile)
        let removed = db.removeComics(ids)
        guard !removed.isEmpty else { return }
        for file in coverFiles {
            covers.removeCoverFile(file)
        }
        for id in removed {
            invalidateComic(id)
        }
        comics = db.listComics()
        selectedIds.subtract(removed)
        if let anchor = anchorId, removed.contains(anchor) { anchorId = nil }
    }

    func rename(id: String, title: String) {
        guard let updated = db.renameComic(id: id, title: title) else { return }
        patch(updated)
    }

    /// 重新扫描（刷新页数与封面；对齐 ipc.ts comic:rescan-many）
    func rescan(_ ids: [String]) async {
        guard !busy, !ids.isEmpty else { return }
        busy = true
        defer { busy = false }

        var updated: [Comic] = []
        var failed: [BatchRescanResult.Failure] = []
        for id in ids {
            guard let c = db.getComic(id: id) else { continue }
            invalidateComic(id)
            do {
                let list = try scanSource(sourceType: c.sourceType, sourcePath: c.sourcePath)
                guard !list.isEmpty else {
                    throw SourceError("这本漫画里没有页面")
                }
                var u = db.setPageCount(id: id, pageCount: list.count) ?? c
                if let regenerated = covers.regenerateCover(for: u, db: db, now: now()) {
                    u = regenerated
                }
                updated.append(u)
            } catch let e as SourceError {
                failed.append(.init(id: id, title: c.title, error: e.message))
            } catch {
                failed.append(.init(id: id, title: c.title, error: "重新扫描失败，文件可能已损坏"))
            }
        }

        comics = db.listComics()
        if !updated.isEmpty { toasts.show(.success, "已刷新 \(updated.count) 本") }
        for f in failed.prefix(3) {
            toasts.show(.error, "《\(f.title)》：\(f.error)")
        }
        if failed.count > 3 {
            toasts.show(.error, "另有 \(failed.count - 3) 本刷新失败")
        }
    }

    // MARK: 类型标签

    func setStyle(_ ids: [String], style: ComicStyle?) {
        guard !ids.isEmpty else { return }
        let changed = db.setComicsStyle(ids, style: style)
        guard !changed.isEmpty else { return }
        for c in changed { patch(c) }
        if let style {
            toasts.show(.success, "已把 \(changed.count) 本标为「\(ComicStyleInfo.label(style))」，阅读方式已按其习惯设置")
        }
    }

    // MARK: 分类

    func createCategory(name: String) -> Category? {
        let trimmed = String(name.trimmingCharacters(in: .whitespaces).prefix(Limits.categoryNameMax))
        guard !trimmed.isEmpty else { return nil }
        guard !categories.contains(where: { $0.name == trimmed }) else {
            toasts.show(.error, "已存在同名分类")
            return nil
        }
        let category = db.createCategory(name: trimmed)
        categories = db.listCategories()
        return category
    }

    func updateCategory(id: String, patch: CategoryPatch) {
        var p = patch
        if let name = p.name {
            let trimmed = String(name.trimmingCharacters(in: .whitespaces).prefix(Limits.categoryNameMax))
            guard !trimmed.isEmpty else { return }
            guard !categories.contains(where: { $0.id != id && $0.name == trimmed }) else {
                toasts.show(.error, "已存在同名分类")
                return
            }
            p.name = trimmed
        }
        guard db.updateCategory(id: id, patch: p) != nil else { return }
        categories = db.listCategories()
        comics = db.listComics()
    }

    func deleteCategory(id: String) {
        guard db.deleteCategory(id: id) else { return }
        categories = db.listCategories()
        comics = db.listComics()
        if categoryFilter == id { categoryFilter = nil }
    }

    func toggleCategory(comicId: String, categoryId: String) {
        guard let updated = db.toggleComicCategory(id: comicId, categoryId: categoryId) else { return }
        patch(updated)
    }

    func assignCategory(_ ids: [String], categoryId: String, add: Bool) {
        let changed = db.setComicsCategory(ids, categoryId: categoryId, add: add)
        guard !changed.isEmpty else { return }
        for c in changed { patch(c) }
    }

    func categoryCount(_ categoryId: String) -> Int {
        comics.filter { $0.categoryIds.contains(categoryId) }.count
    }

    func categoryColor(_ categoryId: String) -> String? {
        categories.first { $0.id == categoryId }?.color
    }

    // MARK: 多选

    func toggleSelect(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
        anchorId = id
    }

    /// Shift 连选：锚点到目标之间的可见项（替换当前选择）
    func selectRange(to id: String) {
        let list = visible
        guard let anchor = anchorId ?? selectedIds.first,
              let a = list.firstIndex(where: { $0.id == anchor }),
              let b = list.firstIndex(where: { $0.id == id }) else { return }
        let range = a <= b ? a...b : b...a
        selectedIds = Set(list[range].map(\.id))
    }

    func selectAllVisible() {
        let list = visible
        selectedIds = Set(list.map(\.id))
        anchorId = list.last?.id
    }

    func clearSelection() {
        selectedIds = []
        anchorId = nil
    }

    var allVisibleSelected: Bool {
        let list = visible
        return !list.isEmpty && list.allSatisfy { selectedIds.contains($0.id) }
    }

    var isSelectionActive: Bool { !selectedIds.isEmpty }

    // MARK: 备份 / 恢复（桌面版格式互通）

    /// 导出备份为 zip 文件（供分享面板交付）；返回临时文件 URL
    func exportBackup() -> URL? {
        let stamp = BackupCodec.folderName(now: now())
        let tmpRoot = NSTemporaryDirectory() + "/backup-export-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpRoot) }
        do {
            try FileManager.default.createDirectory(atPath: tmpRoot, withIntermediateDirectories: true)
            let result = BackupCodec.export(db: db, parentDir: tmpRoot, coversDir: db.coversDir(), now: now())
            guard result.ok, let dir = result.path else {
                toasts.show(.error, result.error ?? "导出备份失败")
                return nil
            }
            let data = try BackupCodec.zipDirectory(dir)
            let out = NSTemporaryDirectory() + "/\(stamp).comicreaderbackup"
            try data.write(to: URL(fileURLWithPath: out))
            toasts.show(.success, "已导出 \(result.comics ?? 0) 本漫画的备份")
            return URL(fileURLWithPath: out)
        } catch {
            toasts.show(.error, "导出备份失败：\(error.localizedDescription)")
            return nil
        }
    }

    /// 从备份 zip 恢复（合并 / 覆盖）
    @discardableResult
    func restoreBackup(from url: URL, mode: RestoreMode) -> RestoreResult? {
        let tmpRoot = NSTemporaryDirectory() + "/backup-restore-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpRoot) }
        do {
            let data = try Data(contentsOf: url)
            try BackupCodec.unzip(data, to: tmpRoot)
            let result = BackupCodec.restore(
                fromBackupDir: tmpRoot, mode: mode,
                db: db, coversDir: db.coversDir(), now: now()
            )
            guard result.ok else {
                toasts.show(.error, result.error ?? "恢复备份失败")
                return result
            }
            // 恢复后整体刷新（含设置——覆盖恢复会带回备份里的设置）
            settings.load()
            comics = db.listComics()
            categories = db.listCategories()
            if mode == .merge {
                toasts.show(.success, "已合并导入 \(result.imported ?? 0) 本（跳过 \(result.skipped ?? 0) 本）")
            } else {
                toasts.show(.success, "已恢复 \(result.imported ?? 0) 本漫画")
            }
            return result
        } catch {
            toasts.show(.error, "恢复备份失败：\(error.localizedDescription)")
            return nil
        }
    }

    // MARK: 私有

    private func patch(_ comic: Comic) {
        if let idx = comics.firstIndex(where: { $0.id == comic.id }) {
            comics[idx] = comic
        } else {
            comics.append(comic)
        }
    }
}
