import Foundation

// MARK: - 每本漫画的页元数据 sidecar（页内进度恢复 + 跨会话高度学习）
//
// 存两样东西：稀疏的每页宽高比（h/w，读到的页面自然尺寸被动学习）与
// 滚动模式的页内分数进度。选 sidecar 而非并入 library.json：
// 进度回写是 5s 防抖的全库 JSON 重编码，比率入库会把每次进度写放大
// ~2KB/本×全库；sidecar 零 schema 迁移、零桌面互通风险（桌面不可见）。
//
// 内存只持当前打开的一本（load(comicId:) 切换）。

/// 单本漫画的页元数据
public struct PageMeta: Codable, Equatable {
    /// 结构版本（当前恒 1）
    public var version: Int
    /// 稀疏页宽高比（h/w），键为页码
    public var ratios: [Int: Double]
    /// 滚动模式上次停留页
    public var scrollPage: Int?
    /// 滚动模式页内分数 [0,1)（相对页顶）
    public var scrollFraction: Double?

    public init(
        version: Int = 1,
        ratios: [Int: Double] = [:],
        scrollPage: Int? = nil,
        scrollFraction: Double? = nil
    ) {
        self.version = version
        self.ratios = ratios
        self.scrollPage = scrollPage
        self.scrollFraction = scrollFraction
    }
}

public final class PageMetaStore: @unchecked Sendable {
    private let dir: String
    private let saver: DebouncedSaver
    private let lock = NSLock()
    private var comicId: String?
    private var meta = PageMeta()

    public init(dir: String, clock: DebouncedSaver.Clock = .live()) {
        self.dir = dir
        self.saver = DebouncedSaver(clock: clock)
        // 全部存储属性就绪后再接写盘回调（避免 init 中捕获未完成的 self）
        saver.onFire { [weak self] in
            self?.writeToDisk()
        }
    }

    // MARK: 载入 / 切换

    /// 载入一本漫画的元数据（打开时调用）。损坏文件改名留证后按空表启动
    /// （镜像 LibraryDatabase.load 的容错行为）
    public func load(comicId: String) -> PageMeta {
        lock.lock(); defer { lock.unlock() }
        self.comicId = comicId
        meta = PageMeta()
        let path = filePath(comicId)
        guard let data = FileManager.default.contents(atPath: path) else { return meta }
        do {
            meta = try JSONDecoder().decode(PageMeta.self, from: data)
        } catch {
            let backup = path + ".corrupt-\(Int(Date().timeIntervalSince1970))"
            try? FileManager.default.moveItem(atPath: path, toPath: backup)
        }
        return meta
    }

    /// 当前内存态快照
    public func current() -> PageMeta {
        lock.lock(); defer { lock.unlock() }
        return meta
    }

    // MARK: 更新（锁内读改写，防抖落盘）

    /// 记一页的宽高比；变化超过阈值才标脏
    public func setRatio(index: Int, ratio: Double) {
        lock.lock(); defer { lock.unlock() }
        guard index >= 0, ratio > 0, ratio.isFinite else { return }
        if let old = meta.ratios[index], abs(old - ratio) <= 0.01 { return }
        meta.ratios[index] = ratio
        saver.saveLazy()
    }

    /// 记滚动模式的页内进度
    public func setScroll(page: Int, fraction: Double) {
        lock.lock(); defer { lock.unlock() }
        guard page >= 0 else { return }
        let clamped = min(max(0, fraction), 0.999)
        if meta.scrollPage == page,
           let old = meta.scrollFraction, abs(old - clamped) <= 0.002 { return }
        meta.scrollPage = page
        meta.scrollFraction = clamped
        saver.saveLazy()
    }

    /// 按页数截断越界的比率键（打开时页数变少用）
    public func truncate(pageCount: Int) {
        lock.lock(); defer { lock.unlock() }
        let kept = meta.ratios.filter { $0.key < pageCount }
        guard kept.count != meta.ratios.count else { return }
        meta.ratios = kept
        saver.saveLazy()
    }

    // MARK: 落盘

    public func flushSync() {
        saver.flushSync()
    }

    private func filePath(_ comicId: String) -> String {
        dir + "/" + comicId + ".json"
    }

    private func writeToDisk() {
        lock.lock()
        guard let comicId else { lock.unlock(); return }
        let snapshot = meta
        let path = filePath(comicId)
        lock.unlock()

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let tmp = path + ".tmp"
        guard (try? data.write(to: URL(fileURLWithPath: tmp))) != nil else { return }
        // 原子替换（对齐 LibraryDatabase.writeToDisk 的语义）
        if fm.fileExists(atPath: path) {
            do {
                _ = try fm.replaceItemAt(
                    URL(fileURLWithPath: path),
                    withItemAt: URL(fileURLWithPath: tmp)
                )
            } catch {
                try? fm.removeItem(atPath: path)
                try? fm.moveItem(atPath: tmp, toPath: path)
            }
        } else {
            try? fm.moveItem(atPath: tmp, toPath: path)
        }
    }
}
