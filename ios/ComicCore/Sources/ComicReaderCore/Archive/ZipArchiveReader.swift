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
            guard let archive = Archive(url: url, accessMode: .read) else {
                throw SourceError("无法读取压缩包，文件可能已损坏或不是有效的 ZIP/CBZ", path: path)
            }
            return Handle(archive: archive, url: url)
        },
        close: { _ in }
    ))

    public init() {}

    public func list(_ file: String) throws -> [ArchiveEntry] {
        let handle = try awaitBlocking { try await self.cache.acquire(file) }
        return handle.archive.map { entry in
            ArchiveEntry(name: entry.path, isDirectory: entry.type == .directory)
        }
    }

    public func read(_ file: String, entry: String) throws -> Data {
        let handle = try awaitBlocking { try await self.cache.acquire(file) }
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
