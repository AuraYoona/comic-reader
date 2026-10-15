import Foundation
#if canImport(UnrarKitLocal)
import UnrarKitLocal
#endif

// MARK: - RAR / CBR 适配器（src/main/archive/rar.ts 的移植）
//
// vendored UnrarKit（官方 UnRAR 6.12，RAR4 + RAR5 完整支持）。
// 桌面版常量：RAR_MAX_OPEN = 1、RAR_IDLE_MS = 45s、RAR_MAX_BYTES = 1.5 GiB。
// URKArchive 按条目随机解压，不需要整体载入内存；句柄由 HandleCache 统一管理。

#if canImport(UnrarKitLocal)
public final class RarArchiveReader: ArchiveReader {
    /// 桌面版 RAR_MAX_BYTES（iOS 上 URKArchive 内存映射文件，保留同样的防护上限）
    static let maxBytes: Int = 1_610_612_736 // 1.5 GiB

    private final class Handle {
        let archive: URKArchive
        init(archive: URKArchive) { self.archive = archive }
    }

    private let cache = HandleCache<Handle>(options: HandleCacheOptions<Handle>(
        max: 1,
        idleSeconds: 45,
        open: { path in
            let url = URL(fileURLWithPath: path)
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            let size = (attrs?[.size] as? Int) ?? 0
            if size > Self.maxBytes {
                throw SourceError("这个 RAR 超过 1.5 GB，解压需要整体载入内存，暂不支持", path: path)
            }
            guard let archive = try? URKArchive(url: url) else {
                throw SourceError("读取 RAR 失败，文件可能已损坏或不是有效的 RAR/CBR", path: path)
            }
            return Handle(archive: archive)
        },
        close: { _ in }
    ))

    public init() {}

    public func list(_ file: String) throws -> [ArchiveEntry] {
        let handle = try awaitBlocking { try await self.cache.acquire(file) }
        var error: NSError?
        guard let infos = handle.archive.listFileInfos(&error) else {
            throw Self.translate(error, path: file)
        }
        return infos.map { info in
            ArchiveEntry(name: info.filename, isDirectory: info.isDirectory)
        }
    }

    public func read(_ file: String, entry: String) throws -> Data {
        let handle = try awaitBlocking { try await self.cache.acquire(file) }
        var error: NSError?
        guard let data = handle.archive.extractDataFromFile(entry, error: &error) else {
            throw Self.translate(error, path: file, entry: entry)
        }
        return data
    }

    public func release(_ file: String) {
        cache.release(file)
    }

    public func releaseAll() {
        cache.releaseAll()
    }

    /// 把 unrar 的错误码翻译成用户能看懂的话（对齐桌面版 rarError）
    static func translate(_ error: NSError?, path: String, entry: String? = nil) -> SourceError {
        guard let error else {
            return SourceError("读取 RAR 失败，文件可能已损坏或不是有效的 RAR/CBR", path: path)
        }
        // URKErrorCode 对应 UnRAR 的 ERAR_* 码
        let code = URKErrorCode(rawValue: error.code)
        switch code {
        case .missingPassword, .badPassword:
            return SourceError("这个 RAR 有密码保护，暂不支持加密的压缩包", path: path)
        case .unknownFormat, .badArchive:
            return SourceError("无法识别的 RAR，文件可能已损坏，或是分卷压缩包的其中一卷", path: path)
        case .badData:
            return SourceError("RAR 数据校验失败，文件可能已损坏", path: path)
        case .noMemory:
            return SourceError("内存不足，无法解压这个 RAR", path: path)
        default:
            if let entry {
                return SourceError("解压文件内页面失败：\(entry)", path: path)
            }
            return SourceError("读取 RAR 失败，文件可能已损坏或不是有效的 RAR/CBR", path: path)
        }
    }
}
#endif
