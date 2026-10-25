import Foundation

// MARK: - 压缩包句柄的 LRU 缓存（src/main/archive/handleCache.ts 的移植）
//
// 阅读时会按页反复读同一个文件，每页重新打开一次代价很高（ZIP 要重解中央目录，
// RAR / PDF 要重新把整个文件读进内存）。这里按「文件路径 → 已打开的句柄」缓存，
// 空闲超时或超过上限时释放。同一个文件的并发打开会合并成一次。

public struct HandleCacheOptions<T> {
    /// 同时保留的句柄上限，超出时按最旧淘汰
    public let max: Int
    /// 空闲多久自动释放（秒）
    public let idleSeconds: Double
    /// 打开句柄
    public let open: @Sendable (String) throws -> T
    /// 释放句柄，不允许抛错
    public let close: @Sendable (T) -> Void

    public init(
        max: Int,
        idleSeconds: Double,
        open: @escaping @Sendable (String) throws -> T,
        close: @escaping @Sendable (T) -> Void
    ) {
        self.max = max
        self.idleSeconds = idleSeconds
        self.open = open
        self.close = close
    }
}

public final class HandleCache<T>: @unchecked Sendable {
    private struct Entry {
        let value: T
        var timer: DispatchSourceTimer?
    }

    private let options: HandleCacheOptions<T>
    private var entries: [String: Entry] = [:]     // 字典 + 手动维护 LRU 顺序
    private var order: [String] = []                // 头部最旧、尾部最新
    private var pending: [String: Task<T, Error>] = [:]
    private let queue = DispatchQueue(label: "com.aurayoona.comicreader.handlecache")

    public init(options: HandleCacheOptions<T>) {
        self.options = options
    }

    private func scheduleRelease(_ key: String) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + options.idleSeconds)
        timer.setEventHandler { [weak self] in
            // handler 已在本队列上执行，必须直接调 releaseLocked；
            // 走 release 的 queue.sync 会向自身串行队列同步重入，永久死锁
            self?.releaseLocked(key)
        }
        timer.resume()
        return timer
    }

    /// 命中：刷新计时器并把 key 移到 LRU 尾部
    private func touch(_ key: String, _ entry: inout Entry) {
        entry.timer?.cancel()
        entry.timer = scheduleRelease(key)
        order.removeAll { $0 == key }
        order.append(key)
    }

    public func acquire(_ key: String) async throws -> T {
        var hit: T?
        var task: Task<T, Error>?

        // 缓存命中与「注册打开任务」必须在同一个临界区里完成判断：
        // 否则存在竞态——快路径未命中 → 另一个任务打开完成并写入缓存 →
        // 这里再度注册新任务，同一文件被打开两次（并发合并失效）
        queue.sync {
            if var entry = entries[key] {
                touch(key, &entry)
                entries[key] = entry
                hit = entry.value
                return
            }
            if let inflight = pending[key] {
                task = inflight
                return
            }
            let newTask = Task<T, Error> { [weak self] in
                guard let self else { throw SourceError("handle cache released") }
                do {
                    let value = try self.options.open(key)
                    // 打开完成后入缓存（打开期间可能已被 release：新句柄天然是最新的，直接入缓存即可）
                    self.insert(key: key, value: value)
                    return value
                } catch {
                    // 失败时在任务内部自清理 pending（对齐桌面版 .catch 里 delete）：
                    // 否则失败的任务会留在表里被后续调用者观察到
                    self.queue.sync { self.pending[key] = nil }
                    throw error
                }
            }
            pending[key] = newTask
            task = newTask
        }

        if let hit { return hit }
        guard let task else { throw SourceError("handle cache released") }
        return try await task.value
    }

    /// 打开完成后把句柄放入缓存；先淘汰超限的最旧条目
    private func insert(key: String, value: T) {
        queue.sync {
            pending[key] = nil
            while entries.count >= options.max {
                guard let oldest = order.first else { break }
                releaseLocked(oldest)
            }
            var entry = Entry(value: value, timer: nil)
            entry.timer = scheduleRelease(key)
            entries[key] = entry
            order.append(key)
        }
    }

    private func releaseLocked(_ key: String) {
        guard let entry = entries[key] else { return }
        entry.timer?.cancel()
        entries[key] = nil
        order.removeAll { $0 == key }
        // 关闭失败无需处理，句柄已从缓存移除
        options.close(entry.value)
    }

    /// 主动释放某个句柄（文件被替换、读取失败重试时用）
    public func release(_ key: String) {
        queue.sync { releaseLocked(key) }
    }

    public func releaseAll() {
        queue.sync {
            for key in order { releaseLocked(key) }
        }
    }
}
