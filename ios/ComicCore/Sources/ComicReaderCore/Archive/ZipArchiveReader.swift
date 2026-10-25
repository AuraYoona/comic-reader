import Foundation
#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

// MARK: - ZIP / CBZ 适配器（src/main/archive/zip.ts 的移植）
//
// ZIPFoundation 按条目随机读取（Entry.extract 到 Data），不需要整体解压。
// 桌面版常量：ZIP_MAX_OPEN = 4 句柄、ZIP_IDLE_MS = 60s。

#if canImport(ZIPFoundation)
public final class ZipArchiveReader: ArchiveReader {
    private final class Handle {
        let archive: Archive
        let url: URL
        /// ZIPFoundation 的 Archive 终身持有单个 FILE* 且 extract 全程无锁，
        /// 并发读同一文件会互相踩踏读位置（fseek 交错 → 解压出损坏数据）。
        /// 对齐 RAR 路径 URKArchive 自带的 @synchronized(threadLock) 串行化
        let ioLock = NSLock()
        init(archive: Archive, url: URL) {
            self.archive = archive
            self.url = url
        }
    }

    /// 每本漫画的条目名索引（中央目录只在打开时解析一次）
    private let cache = HandleCache<Handle>(options: HandleCacheOptions<Handle>(
        max: 4,
        idleSeconds: 60,
        open: { path in
            let url = URL(fileURLWithPath: path)
            do {
                // ZIPFoundation 0.9.19+ 的 throwing 初始化器（failable 版本已废弃）
                let archive = try Archive(url: url, accessMode: .read)
                return Handle(archive: archive, url: url)
            } catch {
                throw SourceError("无法读取压缩包，文件可能已损坏或不是有效的 ZIP/CBZ", path: path)
            }
        },
        close: { _ in }
    ))

    public init() {}

    public func list(_ file: String) throws -> [ArchiveEntry] {
        let handle = try awaitBlocking { try await self.cache.acquire(file) }
        handle.ioLock.lock()
        defer { handle.ioLock.unlock() }
        return handle.archive.map { entry in
            ArchiveEntry(name: entry.path, isDirectory: entry.type == .directory)
        }
    }

    public func read(_ file: String, entry: String) throws -> Data {
        let handle = try awaitBlocking { try await self.cache.acquire(file) }
        // 条目下标查找同样是共享 FILE* 上的 IO（惰性线性扫中央目录，
        // 每条 fseek+fread），必须与 extract 同一把锁——只锁 extract 挡不住
        // 「一个线程持锁顺序读、另一个线程在锁外 fseek」的交错踩踏
        handle.ioLock.lock()
        defer { handle.ioLock.unlock() }
        guard let archiveEntry = handle.archive[entry] else {
            throw SourceError("压缩包内没有这个条目：\(entry)", path: file)
        }
        var data = Data()
        _ = try handle.archive.extract(archiveEntry, bufferSize: 64 * 1024) { chunk in
            data.append(chunk)
        }
        return data
    }

    public func release(_ file: String) {
        cache.release(file)
    }

    public func releaseAll() {
        cache.releaseAll()
    }
}
#endif
