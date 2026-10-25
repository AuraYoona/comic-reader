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

    // MARK: 文件名编码修复（GBK zip）

    /// CP437（DOS 美国码页，ZIPFoundation 对未设 UTF-8 标志条目的解码方式）
    private static let cp437: String.Encoding = {
        let raw = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x400))
        return String.Encoding(rawValue: raw)
    }()

    /// GB18030（GBK 的超集；国内压缩工具未设 UTF-8 标志时实际写入的编码）
    private static let gb18030: String.Encoding = {
        let raw = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        return String.Encoding(rawValue: raw)
    }()

    /// 修复 zip 条目名：未设 UTF-8 标志的 zip 里，ZIPFoundation 按 CP437 解码，
    /// 国内工具写的 GBK 名字汉字全成乱码（ASCII/数字不受影响）。
    /// CP437 对 256 个字节全映射——字符串能无损还原回原始字节，再依次尝试
    /// UTF-8（漏打标志的）、GB18030。带 UTF-8 标志的正常名字含 CP437 之外
    /// 的字符，还原字节必然失败，原样返回（天然的方向判别）
    static func repairEntryName(_ name: String) -> String {
        guard let raw = name.data(using: Self.cp437) else { return name }
        guard raw.contains(where: { $0 >= 0x80 }) else { return name }
        if let utf8 = String(data: raw, encoding: .utf8) { return utf8 }
        if let gbk = String(data: raw, encoding: Self.gb18030) { return gbk }
        return name
    }

    public func list(_ file: String) throws -> [ArchiveEntry] {
        let handle = try awaitBlocking { try await self.cache.acquire(file) }
        handle.ioLock.lock()
        defer { handle.ioLock.unlock() }
        return handle.archive.map { entry in
            ArchiveEntry(name: Self.repairEntryName(entry.path), isDirectory: entry.type == .directory)
        }
    }

    public func read(_ file: String, entry: String) throws -> Data {
        let handle = try awaitBlocking { try await self.cache.acquire(file) }
        // 条目下标查找同样是共享 FILE* 上的 IO（惰性线性扫中央目录，
        // 每条 fseek+fread），必须与 extract 同一把锁——只锁 extract 挡不住
        // 「一个线程持锁顺序读、另一个线程在锁外 fseek」的交错踩踏。
        // 页面列表存的是修复后的名字，查找时按修复后路径比对
        handle.ioLock.lock()
        defer { handle.ioLock.unlock() }
        guard let archiveEntry = handle.archive.first(where: {
            Self.repairEntryName($0.path) == entry
        }) else {
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

extension ZipArchiveReader {
    /// 整包解压到目标目录（章节并入用）：条目名经 GBK 修复后按原始相对
    /// 路径落盘（保留「第03话/…」的目录结构）；剥离路径非法字符、丢弃
    /// 含 .. 的条目（防穿越）与隐藏文件；重名加序号避让。
    /// 逐条迭代与 extract 都在共享 FILE* 上做 IO——整段持 ioLock，
    /// 避免与并发读页互相踩踏。返回写出的文件数
    @discardableResult
    public func extractAll(_ file: String, toDirectory dir: String) throws -> Int {
        let handle = try awaitBlocking { try await self.cache.acquire(file) }
        let fm = FileManager.default
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let invalid = CharacterSet(charactersIn: "/\\:?*\"<>|").union(.controlCharacters)

        handle.ioLock.lock()
        defer { handle.ioLock.unlock() }

        var written = 0
        var usedPaths = Set<String>()
        for entry in handle.archive where entry.type != .directory {
            let name = Self.repairEntryName(entry.path)
            let parts = name.split(separator: "/").map(String.init)
            guard !parts.isEmpty, !parts.contains(".."), let last = parts.last, !last.isEmpty else {
                continue
            }
            var safeParts: [String] = []
            for part in parts {
                let safe = part.components(separatedBy: invalid).joined(separator: "_")
                guard !safe.isEmpty, !safe.hasPrefix(".") else {
                    safeParts = []
                    break
                }
                safeParts.append(safe)
            }
            guard !safeParts.isEmpty else { continue }

            var dest = (dir as NSString).appendingPathComponent(safeParts.joined(separator: "/"))
            if usedPaths.contains(dest) || fm.fileExists(atPath: dest) {
                let ext = (dest as NSString).pathExtension
                let stem = (dest as NSString).deletingPathExtension
                var n = 2
                repeat {
                    let candidate = ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)"
                    dest = candidate
                    n += 1
                } while usedPaths.contains(dest) || fm.fileExists(atPath: dest)
            }
            usedPaths.insert(dest)

            try fm.createDirectory(
                atPath: (dest as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            var data = Data()
            _ = try handle.archive.extract(entry, bufferSize: 64 * 1024) { chunk in
                data.append(chunk)
            }
            try data.write(to: URL(fileURLWithPath: dest))
            written += 1
        }
        return written
    }
}
#endif
