import Foundation

// MARK: - 基于单个 JSON 文件的本地数据库（src/main/store/db.ts Database 类的移植）
//
// - 内存即时更新 + 防抖落盘；「写临时文件再改名」保证原子性；退出/进后台时同步 flush
// - 结构性改动（400ms）与阅读进度（5000ms）分两档防抖，避免翻页把整库反复重写
// - 加载时经过 migrations 管线逐级升级，迁移前把原文件备份为 library.json.v<N>.bak
// - 解析失败时备份损坏文件并从空库启动，绝不让应用起不来

public final class LibraryDatabase: @unchecked Sendable {
    /// 结构性改动的落盘防抖（秒）
    public static let saveDebounceSeconds: Double = 0.4
    /// 阅读进度的落盘防抖（秒），特意比结构性改动长得多
    public static let progressSaveDebounceSeconds: Double = 5.0

    private let lock = NSRecursiveLock()
    private let paths: AppPaths
    private let saver: DebouncedSaver
    private let now: @Sendable () -> Double
    private var data: LibraryFile = LibraryFile()

    /// 供测试观察落盘次数
    public private(set) var writeCount: Int = 0

    public init(paths: AppPaths, clock: DebouncedSaver.Clock = .live(), now: (@Sendable () -> Double)? = nil) {
        self.paths = paths
        self.now = now ?? { Date().timeIntervalSince1970 * 1000 }
        self.saver = DebouncedSaver(clock: clock)
        // 全部存储属性就绪后再接写盘回调（避免 init 中捕获未完成的 self）
        saver.onFire { [weak self] in
            self?.writeToDisk()
        }
    }

    public func libraryPath() -> String { paths.libraryPath }
    public func coversDir() -> String { paths.coversDir }

    // MARK: 加载

    public func load() {
        lock.lock(); defer { lock.unlock() }
        let filePath = paths.libraryPath
        let fm = FileManager.default

        guard fm.fileExists(atPath: filePath) else {
            data = LibraryFile()
            return
        }

        let rawText: String
        do {
            rawText = try String(contentsOfFile: filePath, encoding: .utf8)
        } catch {
            data = LibraryFile()
            return
        }

        guard let parsed = try? JSONSerialization.jsonObject(with: Data(rawText.utf8)) else {
            // 解析失败：备份损坏文件并从空库启动
            let backup = "\(filePath).corrupt-\(Int(now()))"
            try? rawText.write(toFile: backup, atomically: true, encoding: .utf8)
            data = LibraryFile()
            return
        }

        let normalized = normalizeLibraryData(parsed, now: now())
        if normalized.migrated {
            // 迁移前把原文件备份，出问题可回退
            let backup = "\(filePath).v\(normalized.fromVersion).bak"
            try? rawText.write(toFile: backup, atomically: true, encoding: .utf8)
        }
        if normalized.fromVersion > CURRENT_SCHEMA_VERSION {
            // 本版本一旦写盘就会丢掉未知的新字段，先做一次性备份（保留最早那份）
            let backup = "\(filePath).v\(normalized.fromVersion).bak"
            if !fm.fileExists(atPath: backup) {
                try? rawText.write(toFile: backup, atomically: true, encoding: .utf8)
            }
        }

        data = normalized.data

        if normalized.migrated {
            writeToDisk()
        }
    }

    // MARK: 漫画

    public func listComics() -> [Comic] {
        lock.lock(); defer { lock.unlock() }
        return data.comics
    }

    public func getComic(id: String) -> Comic? {
        lock.lock(); defer { lock.unlock() }
        return data.comics.first { $0.id == id }
    }

    public func upsertComic(_ comic: Comic) {
        lock.lock(); defer { lock.unlock() }
        if let idx = data.comics.firstIndex(where: { $0.id == comic.id }) {
            data.comics[idx] = comic
        } else {
            data.comics.append(comic)
        }
        saver.saveSoon()
    }

    /// 阅读进度回写（reader 偏好浅合并，部分补丁不会擦掉其它偏好）
    @discardableResult
    public func updateProgress(id: String, patch: ProgressPatch) -> Comic? {
        lock.lock(); defer { lock.unlock() }
        guard let idx = data.comics.firstIndex(where: { $0.id == id }) else { return nil }
        var comic = data.comics[idx]
        if let page = patch.lastReadPage {
            comic.lastReadPage = min(max(0, page), max(0, comic.pageCount - 1))
        }
        if let reader = patch.reader {
            comic.reader = mergePrefs(comic.reader, reader)
        }
        comic.lastReadAt = now()
        data.comics[idx] = comic
        saver.saveLazy()
        return comic
    }

    /// 批量移除，返回真正被移除的 id（不存在的会被忽略）
    @discardableResult
    public func removeComics(_ ids: [String]) -> [String] {
        lock.lock(); defer { lock.unlock() }
        let target = Set(ids)
        var removed: [String] = []
        data.comics.removeAll { c in
            if target.contains(c.id) {
                removed.append(c.id)
                return true
            }
            return false
        }
        guard !removed.isEmpty else { return removed }
        if let last = data.settings.lastOpenedComicId, target.contains(last) {
            data.settings.lastOpenedComicId = nil
        }
        saver.saveSoon()
        return removed
    }

    /// 重命名书架标题（只改记录，不动原文件）
    @discardableResult
    public func renameComic(id: String, title: String) -> Comic? {
        lock.lock(); defer { lock.unlock() }
        guard let idx = data.comics.firstIndex(where: { $0.id == id }) else { return nil }
        let trimmed = String(title.trimmingCharacters(in: .whitespaces).prefix(Limits.titleMax))
        data.comics[idx].title = trimmed
        saver.saveSoon()
        return data.comics[idx]
    }

    /// 改绑来源路径（整库搬盘后的重定位）
    @discardableResult
    public func setSourcePath(id: String, sourcePath: String) -> Comic? {
        lock.lock(); defer { lock.unlock() }
        guard let idx = data.comics.firstIndex(where: { $0.id == id }) else { return nil }
        data.comics[idx].sourcePath = sourcePath
        saver.saveSoon()
        return data.comics[idx]
    }

    /// 更新页数（重新扫描后写回）
    @discardableResult
    public func setPageCount(id: String, pageCount: Int) -> Comic? {
        lock.lock(); defer { lock.unlock() }
        guard let idx = data.comics.firstIndex(where: { $0.id == id }) else { return nil }
        data.comics[idx].pageCount = pageCount
        data.comics[idx].lastReadPage = min(data.comics[idx].lastReadPage, max(0, pageCount - 1))
        data.comics[idx].bookmarks = data.comics[idx].bookmarks.filter { $0 < pageCount }
        saver.saveSoon()
        return data.comics[idx]
    }

    /// 更新封面文件名（重新生成封面后写回；传 nil 清空）
    @discardableResult
    public func setCoverFile(id: String, coverFile: String?) -> Comic? {
        lock.lock(); defer { lock.unlock() }
        guard let idx = data.comics.firstIndex(where: { $0.id == id }) else { return nil }
        data.comics[idx].coverFile = coverFile
        saver.saveSoon()
        return data.comics[idx]
    }

    /// 增删一个书签页，返回更新后的记录
    @discardableResult
    public func toggleBookmark(id: String, page: Int) -> Comic? {
        lock.lock(); defer { lock.unlock() }
        guard let idx = data.comics.firstIndex(where: { $0.id == id }) else { return nil }
        let target = max(0, page)
        var marks = data.comics[idx].bookmarks
        if let hit = marks.firstIndex(of: target) {
            marks.remove(at: hit)
        } else {
            marks.append(target)
            marks.sort()
        }
        data.comics[idx].bookmarks = marks
        saver.saveSoon()
        return data.comics[idx]
    }

    /// 标记已读时间（打开漫画时）
    @discardableResult
    public func touchLastRead(id: String) -> Comic? {
        lock.lock(); defer { lock.unlock() }
        guard let idx = data.comics.firstIndex(where: { $0.id == id }) else { return nil }
        data.comics[idx].lastReadAt = now()
        saver.saveSoon()
        return data.comics[idx]
    }

    /**
     批量打类型标签，返回真正改动过的记录。
     打标签时把该类型的阅读预设一次性写进每本的阅读偏好——否则之前单独调过的
     模式 / 方向会盖住预设，标签形同虚设；之后在阅读器里再改仍然按本记住。
     传 nil 只摘掉标签，已写入的偏好保持原样。
     */
    @discardableResult
    public func setComicsStyle(_ ids: [String], style: ComicStyle?) -> [Comic] {
        lock.lock(); defer { lock.unlock() }
        let target = Set(ids)
        let preset = style.map { comicStylePreset($0) }
        var changed: [Comic] = []
        for i in data.comics.indices {
            guard target.contains(data.comics[i].id) else { continue }
            if data.comics[i].style == style && preset == nil { continue }
            data.comics[i].style = style
            if let preset {
                data.comics[i].reader = mergePrefs(data.comics[i].reader, preset)
            }
            changed.append(data.comics[i])
        }
        if !changed.isEmpty { saver.saveSoon() }
        return changed
    }

    // MARK: 设置

    public func getSettings() -> AppSettings {
        lock.lock(); defer { lock.unlock() }
        return data.settings
    }

    /// 以「读-改-写」闭包的方式更新设置，结果统一过 sanitize
    @discardableResult
    public func saveSettings(_ mutate: (inout AppSettings) -> Void) -> AppSettings {
        lock.lock(); defer { lock.unlock() }
        var merged = data.settings
        mutate(&merged)
        let encoded = (try? JSONEncoder().encode(merged)) ?? Data()
        let raw = (try? JSONSerialization.jsonObject(with: encoded)) ?? [String: Any]()
        data.settings = sanitizeSettings(raw)
        saver.saveSoon()
        return data.settings
    }

    /// 把一个根目录加进监视列表（已存在则原样返回）
    @discardableResult
    public func addLibraryRoot(_ root: String) -> AppSettings {
        lock.lock(); defer { lock.unlock() }
        let roots = data.settings.libraryRoots
        let key = root.lowercased() // iOS 文件系统默认大小写不敏感
        if roots.contains(where: { $0.lowercased() == key }) { return data.settings }
        return saveSettings { $0.libraryRoots = roots + [root] }
    }

    // MARK: 分类

    public func listCategories() -> [Category] {
        lock.lock(); defer { lock.unlock() }
        return data.categories
    }

    @discardableResult
    public func createCategory(name: String, color: String? = nil) -> Category {
        lock.lock(); defer { lock.unlock() }
        let fallback = Limits.categoryColors[data.categories.count % Limits.categoryColors.count]
        let category = Category(
            id: UUID().uuidString.lowercased(),
            name: name.trimmingCharacters(in: .whitespaces),
            color: (color.flatMap { isValidHexColor($0) ? $0 : nil }) ?? fallback,
            createdAt: now()
        )
        data.categories.append(category)
        saver.saveSoon()
        return category
    }

    @discardableResult
    public func updateCategory(id: String, patch: CategoryPatch) -> Category? {
        lock.lock(); defer { lock.unlock() }
        guard let idx = data.categories.firstIndex(where: { $0.id == id }) else { return nil }
        if let name = patch.name {
            data.categories[idx].name = name.trimmingCharacters(in: .whitespaces)
        }
        if let color = patch.color, isValidHexColor(color) {
            data.categories[idx].color = color
        }
        saver.saveSoon()
        return data.categories[idx]
    }

    /// 删除分类只解除漫画与它的关联，不影响漫画记录本身
    @discardableResult
    public func deleteCategory(id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let before = data.categories.count
        data.categories.removeAll { $0.id == id }
        guard data.categories.count != before else { return false }
        for i in data.comics.indices where data.comics[i].categoryIds.contains(id) {
            data.comics[i].categoryIds.removeAll { $0 == id }
        }
        saver.saveSoon()
        return true
    }

    /// 把漫画加入/移出一个分类：按数据库当前归属决定方向，界面的过期快照不会互相覆盖
    @discardableResult
    public func toggleComicCategory(id: String, categoryId: String) -> Comic? {
        lock.lock(); defer { lock.unlock() }
        guard let idx = data.comics.firstIndex(where: { $0.id == id }) else { return nil }
        // 分类已不存在（可能刚被删除）时不变更；删除分类时已剥离过关联
        guard data.categories.contains(where: { $0.id == categoryId }) else {
            return data.comics[idx]
        }
        if data.comics[idx].categoryIds.contains(categoryId) {
            data.comics[idx].categoryIds.removeAll { $0 == categoryId }
        } else {
            data.comics[idx].categoryIds.append(categoryId)
        }
        saver.saveSoon()
        return data.comics[idx]
    }

    /// 批量设置分类：add=true 全部加入，false 全部移出。方向由调用方指定，结果确定。
    @discardableResult
    public func setComicsCategory(_ ids: [String], categoryId: String, add: Bool) -> [Comic] {
        lock.lock(); defer { lock.unlock() }
        guard data.categories.contains(where: { $0.id == categoryId }) else { return [] }
        let target = Set(ids)
        var changed: [Comic] = []
        for i in data.comics.indices {
            guard target.contains(data.comics[i].id) else { continue }
            let has = data.comics[i].categoryIds.contains(categoryId)
            if add == has { continue }
            if add {
                data.comics[i].categoryIds.append(categoryId)
            } else {
                data.comics[i].categoryIds.removeAll { $0 == categoryId }
            }
            changed.append(data.comics[i])
        }
        if !changed.isEmpty { saver.saveSoon() }
        return changed
    }

    // MARK: 备份 / 恢复

    /// 导出用的深拷贝快照
    public func snapshot() -> LibraryFile {
        lock.lock(); defer { lock.unlock() }
        return data
    }

    /// 整库替换（恢复备份用），立即落盘
    public func replaceAll(_ newData: LibraryFile) {
        lock.lock(); defer { lock.unlock() }
        data = LibraryFile(
            version: CURRENT_SCHEMA_VERSION,
            settings: newData.settings,
            comics: newData.comics,
            categories: newData.categories
        )
        flushSync()
    }

    // MARK: 落盘

    private func writeToDisk() {
        lock.lock(); defer { lock.unlock() }
        let filePath = paths.libraryPath
        guard !filePath.isEmpty else { return }
        do {
            let encoder = JSONEncoder()
            // 不做缩进：上千本时能省掉一半体积（与桌面版一致）
            let json = try encoder.encode(data)
            let tmp = filePath + ".tmp"
            try json.write(to: URL(fileURLWithPath: tmp))
            // 原子替换：先写临时文件再改名（对齐桌面版 fs.renameSync 语义：
            // 目标存在则原子替换，不存在则直接落位）
            let fm = FileManager.default
            if fm.fileExists(atPath: filePath) {
                do {
                    _ = try fm.replaceItemAt(
                        URL(fileURLWithPath: filePath),
                        withItemAt: URL(fileURLWithPath: tmp)
                    )
                } catch {
                    // 个别平台 replaceItemAt 不可用：回退为「移除后改名」
                    try? fm.removeItem(atPath: filePath)
                    try fm.moveItem(atPath: tmp, toPath: filePath)
                }
            } else {
                try fm.moveItem(atPath: tmp, toPath: filePath)
            }
            writeCount += 1
        } catch {
            // 保存失败不抛出：内存数据仍可用，下次防抖再试
        }
    }

    /// 应用退出 / 进入后台前同步写盘
    public func flushSync() {
        saver.flushSync()
    }
}

// MARK: - 辅助

/// reader 偏好浅合并：补丁里为 nil 的字段不会擦掉原值
func mergePrefs(_ base: ComicReaderPrefs, _ patch: ComicReaderPrefs) -> ComicReaderPrefs {
    ComicReaderPrefs(
        mode: patch.mode ?? base.mode,
        zoom: patch.zoom ?? base.zoom,
        zoomScale: patch.zoomScale ?? base.zoomScale,
        direction: patch.direction ?? base.direction,
        pageOffset: patch.pageOffset ?? base.pageOffset,
        autoCrop: patch.autoCrop ?? base.autoCrop,
        autoScroll: patch.autoScroll ?? base.autoScroll
    )
}
