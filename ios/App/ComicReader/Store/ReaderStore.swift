import Foundation
import ComicReaderCore

// MARK: - 阅读器状态机（src/renderer/src/store/reader.ts 的移植）
//
// 每本漫画独立记住：页码 + 阅读模式 + 缩放 + 方向 + 双页偏移 + 裁边开关 + 平滑滚动。
// 进度回写 900ms 防抖（落盘本身还有数据库的 5s 长防抖，两层各司其职）。

@MainActor
final class ReaderStore: ObservableObject {
    /// 进度回写防抖（对齐 reader.ts PERSIST_DEBOUNCE_MS = 900）
    static let persistDebounceMs = 900
    /// 「最后一页」提示窗口（对齐 reader.ts END_HINT_MS = 2600）
    static let endHintMs = 2600

    // 状态（对齐 reader.ts 的 store 字段）
    @Published private(set) var active = false
    @Published private(set) var opening = false
    @Published private(set) var error: String?
    @Published private(set) var comic: Comic?
    @Published private(set) var pageCount = 0
    @Published private(set) var page = 0
    @Published private(set) var mode: ReadingMode = .single
    @Published private(set) var zoom: ZoomMode = .fitWidth
    @Published private(set) var scale: Double = 1
    @Published private(set) var direction: ReadingDirection = .ltr
    @Published private(set) var pageOffset: PageOffset = 1
    @Published private(set) var autoCrop = false
    @Published private(set) var autoScroll = false
    @Published private(set) var widePages: Set<Int> = []
    @Published private(set) var bookmarks: [Int] = []
    @Published private(set) var autoTurn = false
    @Published private(set) var thumbStrip = false
    @Published private(set) var endHint = false

    private let db: LibraryDatabase
    private let settings: SettingsStore
    private let pages: PageProvider
    private let meta: PageMetaStore
    private var persistTask: Task<Void, Never>?
    private var endHintTask: Task<Void, Never>?
    /// 打开会话号：open 有了 await 点之后，close 后立即重开时
    /// 旧扫描凭它作废（否则旧结果会把新会话的状态覆盖回去）
    private var openEpoch = 0

    /// 每页宽高比（h/w）——滚动模式占位高度与页内恢复的依据，
    /// 读过的页跨会话记忆（sidecar 持久化）
    @Published private(set) var pageRatios: [Int: Double] = [:]
    /// 滚动模式重开时的页内恢复分数（一次性，视图取走即清；
    /// 仅当目标页比率已知时非 nil——估算高×分数会错位数屏）
    private(set) var restoreFraction: Double?
    /// 滚动模式最近一次上报的页内位置（persistNow 时写入 sidecar）
    private var lastScrollFraction: Double?

    init(db: LibraryDatabase, settings: SettingsStore, pages: PageProvider, meta: PageMetaStore) {
        self.db = db
        self.settings = settings
        self.pages = pages
        self.meta = meta
    }

    // MARK: 打开 / 关闭

    /// 打开漫画：重新扫描来源 → 刷新页数 → 解析偏好（按本覆盖全局）→ 定位到上次页码
    func open(id: String, fromStart: Bool = false) async {
        // 同一会话内的重复 open（连点）忽略；但上一次还在扫描、且已被 close()
        // 的场景必须放行——否则「退出后马上再点开」会被静默丢弃
        guard !opening || !active else { return }
        opening = true
        openEpoch &+= 1
        let epoch = openEpoch
        defer { if epoch == openEpoch { opening = false } }
        error = nil
        active = true

        guard let stored = db.getComic(id: id) else {
            error = "漫画记录不存在"
            return
        }

        // 强制刷新页列表（对齐桌面 comic:open 的 rescan）。扫描走专用队列：
        // 压缩包的 list() 内部经 awaitBlocking 信号量等待，在主线程上同步跑
        // 会把 UI 整个冻住（最坏 30 秒超时）
        invalidateComic(id)
        let list: [String]
        do {
            list = try await scanSourceAsync(sourceType: stored.sourceType, sourcePath: stored.sourcePath)
        } catch let e as SourceError {
            if epoch == openEpoch { error = e.message }
            return
        } catch {
            // 注意：裸 catch 会隐式绑定名为 error 的局部常量，遮蔽同名属性；
            // 必须用 self. 前缀才能写到属性上
            if epoch == openEpoch { self.error = "打开失败，文件可能已损坏" }
            return
        }
        // 扫描等待期间会话可能已被 close() 或被新的 open 接管：放弃，
        // 避免把清空/新会话的状态覆盖回去
        guard epoch == openEpoch, active else { return }
        guard !list.isEmpty else {
            error = "这本漫画里没有页面"
            return
        }

        var updated = db.setPageCount(id: id, pageCount: list.count) ?? stored
        updated = db.touchLastRead(id: id) ?? updated
        settings.update { $0.lastOpenedComicId = id }

        comic = updated
        pageCount = list.count
        bookmarks = updated.bookmarks
        widePages = []

        // 偏好解析：按本覆盖全局（对齐 reader.ts open 151-187）
        let s = settings.settings
        let prefs = updated.reader
        mode = prefs.mode ?? s.defaultMode
        zoom = prefs.zoom ?? s.defaultZoom
        scale = prefs.zoomScale.map { ZoomLimits.clampScale($0) } ?? 1
        direction = prefs.direction ?? s.readingDirection
        pageOffset = prefs.pageOffset ?? (s.doubleCoverSingle ? 1 : 0)
        autoCrop = prefs.autoCrop ?? s.autoCrop
        autoScroll = prefs.autoScroll ?? false
        autoTurn = false
        thumbStrip = false
        clearEndHint()
        page = fromStart ? 0 : min(max(0, updated.lastReadPage), list.count - 1)

        pages.clearCropCache()

        // 页元数据：载入比率表（跨会话高度学习），截断越界键；
        // 页内分数只在滚动模式且目标页比率已知时生效（否则退化为页顶恢复）
        let m = meta.load(comicId: id)
        meta.truncate(pageCount: list.count)
        pageRatios = m.ratios
        restoreFraction = (mode == .scroll && !fromStart)
            ? ((m.scrollFraction != nil && m.ratios[page] != nil) ? m.scrollFraction : nil)
            : nil
        lastScrollFraction = nil

        schedulePersist()
    }

    /// 返回书架：先落进度，再清缓存（对齐 reader.ts close 189-210）
    func close() {
        flushPersist()
        meta.flushSync()
        endHintTask?.cancel()
        endHint = false
        autoTurn = false
        active = false
        error = nil
        comic = nil
        page = 0
        pageCount = 0
        pageRatios = [:]
        restoreFraction = nil
        lastScrollFraction = nil
        pages.clearAll()
    }

    // MARK: 页元数据（阶段2：宽高比学习 / 页内进度）

    /// 视图回报某页的真实宽高比（h/w）：更新内存表并写入 sidecar
    /// （变化超过阈值才算，避免重复标脏）
    func applyRatio(_ index: Int, ratio: Double) {
        guard ratio > 0, ratio.isFinite else { return }
        if let old = pageRatios[index], abs(old - ratio) <= 0.01 { return }
        pageRatios[index] = ratio
        meta.setRatio(index: index, ratio: ratio)
    }

    /// 滚动模式：视口在当前页内的位置（0..<1，视图节流上报）
    func updateScrollFraction(_ fraction: Double) {
        lastScrollFraction = fraction
    }

    /// 取走一次性页内恢复分数（视图挂载时消费）
    func takeRestoreFraction() -> Double? {
        let f = restoreFraction
        restoreFraction = nil
        return f
    }

    // MARK: 翻页

    func setPage(_ target: Int) {
        guard pageCount > 0 else {
            page = 0
            return
        }
        let clamped = min(max(0, Int(Double(target).rounded())), pageCount - 1)
        let changed = clamped != page
        page = clamped
        if endHint { clearEndHint() }
        if changed { schedulePersist() }
    }

    /// 下一页（双页模式按屏步进；到尽头触发最后一页提示）
    func next() {
        guard active, pageCount > 0 else { return }
        if mode == .double {
            let ctx = spreadContext
            if isLastSpread(page, ctx) {
                hitEnd()
                return
            }
            setPage(stepSpread(page, 1, ctx))
        } else {
            if page >= pageCount - 1 {
                hitEnd()
                return
            }
            setPage(page + 1)
        }
    }

    /// 上一页
    func prev() {
        guard active, pageCount > 0 else { return }
        if mode == .double {
            setPage(stepSpread(page, -1, spreadContext))
        } else {
            setPage(page - 1)
        }
    }

    /// 平滑滚动到底（滚动模式自动滚动的「到尽头」等价于翻到最后一页）
    func reachEnd() {
        hitEnd()
    }

    /// 最后一页提示：第一次显示提示，提示期间再触发一次 → 返回书架
    private func hitEnd() {
        if endHint {
            close()
            return
        }
        endHint = true
        autoTurn = false
        endHintTask?.cancel()
        endHintTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ReaderStore.endHintMs) * 1_000_000)
            guard !Task.isCancelled else { return }
            self?.endHint = false
        }
    }

    private func clearEndHint() {
        endHintTask?.cancel()
        endHint = false
    }

    // MARK: 阅读模式 / 缩放 / 方向

    func setMode(_ m: ReadingMode) {
        guard m != mode else { return }
        mode = m
        schedulePersist()
    }

    func setZoom(_ z: ZoomMode) {
        guard z != zoom || scale != 1 else { return }
        zoom = z
        scale = 1 // 换缩放模式时重置倍率（对齐 reader.ts setZoom）
        schedulePersist()
    }

    func setScale(_ value: Double) {
        let clamped = ZoomLimits.clampScale(value)
        guard clamped != scale else { return }
        scale = clamped
        schedulePersist()
    }

    func setDirection(_ d: ReadingDirection) {
        guard d != direction else { return }
        direction = d
        schedulePersist()
    }

    /// 双页配对偏移（封面单独占屏 ↔ 首页配对）
    func togglePageOffset() {
        pageOffset = pageOffset == 1 ? 0 : 1
        schedulePersist()
    }

    func toggleAutoCrop() {
        autoCrop.toggle()
        schedulePersist()
    }

    /// 滚动模式：自动翻页改为匀速向下平滑滚动（条漫）
    func toggleAutoScroll() {
        autoScroll.toggle()
        schedulePersist()
    }

    // MARK: 自动翻页 / 缩略图条 / 跨页

    func toggleAutoTurn() {
        autoTurn.toggle()
    }

    func stopAutoTurn() {
        autoTurn = false
    }

    func toggleThumbStrip() {
        thumbStrip.toggle()
    }

    /// 图片加载后按实际宽高标记跨页（宽/高 ≥ 1.2 才算）
    func markWide(_ index: Int, isWide: Bool) {
        if isWide {
            widePages.insert(index)
        } else if widePages.contains(index) {
            widePages.remove(index)
        }
    }

    // MARK: 书签

    func toggleBookmark() {
        guard let comic else { return }
        guard let updated = db.toggleBookmark(id: comic.id, page: page) else { return }
        self.comic = updated
        bookmarks = updated.bookmarks
    }

    var isCurrentPageBookmarked: Bool {
        bookmarks.contains(page)
    }

    // MARK: 分屏上下文 / 预取

    /// 双页分屏上下文；跨页信息仅在全局「跨页图铺满整屏」开启时参与
    var spreadContext: SpreadContext {
        let wideEnabled = settings.settings.widePageSpread
        let wide = widePages
        return SpreadContext(
            pageCount: pageCount,
            offset: pageOffset,
            isWide: wideEnabled ? { wide.contains($0) } : nil
        )
    }

    /// 当前一屏的页码（单页模式 1 个，双页模式 1–2 个）
    var currentSpread: [Int] {
        guard pageCount > 0 else { return [] }
        return mode == .double ? spreadAt(page, spreadContext) : [page]
    }

    /// 邻页预取偏移（对齐 PagedView.tsx:100）
    var prefetchOffsets: [Int] {
        mode == .double ? [2, 3, -2, -1, 4, 5] : [1, 2, -1, 3]
    }

    func prefetchNeighbors(maxPixelSize: Int) {
        guard let comic else { return }
        pages.prefetch(comic: comic, current: page, offsets: prefetchOffsets, maxPixelSize: maxPixelSize)
    }

    // MARK: 进度回写（900ms 防抖 + 关闭前 flush）

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ReaderStore.persistDebounceMs) * 1_000_000)
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    func persistNow() {
        guard let comic else { return }
        let prefs = ComicReaderPrefs(
            mode: mode,
            zoom: zoom,
            zoomScale: scale,
            direction: direction,
            pageOffset: pageOffset,
            autoCrop: autoCrop,
            autoScroll: autoScroll
        )
        _ = db.updateProgress(id: comic.id, patch: ProgressPatch(lastReadPage: page, reader: prefs))
        // 滚动模式的页内进度双写进 sidecar（页码仍在 library.json，跨端语义不变）
        if mode == .scroll {
            meta.setScroll(page: page, fraction: lastScrollFraction ?? 0)
        }
        // 刷新快照供界面使用（书架卡片进度等）
        if let refreshed = db.getComic(id: comic.id) {
            self.comic = refreshed
        }
    }

    func flushPersist() {
        persistTask?.cancel()
        persistTask = nil
        persistNow()
    }
}
