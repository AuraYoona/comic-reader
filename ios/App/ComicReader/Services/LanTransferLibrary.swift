import Foundation
import ComicReaderCore

// MARK: - 传输服务访问书架
//
// 读数据库（LibraryDatabase 自身带锁）与封面目录，给 /library、/cover、
// /download 提供数据。文件夹漫画下载时用 ZIPFoundation 现打 zip 到临时文件，
// 由连接层流式发送完再删除——不会把整本漫画读进内存。

final class LanTransferLibrary: @unchecked Sendable {
    struct Download {
        let url: URL
        let fileName: String
        let contentType: String
        let size: Int64
        let deleteAfterSend: Bool
    }

    private let db: LibraryDatabase
    private let coversDir: String

    init(db: LibraryDatabase, coversDir: String) {
        self.db = db
        self.coversDir = coversDir
    }

    func count() -> Int {
        db.listComics().count
    }

    /// /library 的 JSON（只暴露网页需要的字段）
    func libraryJSON() -> Data {
        let comics: [[String: Any]] = db.listComics().map { comic in
            let size: Int64 = comic.sourceType == .archive ? Self.fileSize(comic.sourcePath) : 0
            return [
                "id": comic.id,
                "title": comic.title,
                "pages": comic.pageCount,
                "size": size,
                "kind": comic.sourceType.rawValue,
                "hasCover": comic.coverFile != nil,
            ]
        }
        let payload: [String: Any] = ["comics": comics]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{\"comics\":[]}".utf8)
    }

    func cover(id: String) throws -> (data: Data, contentType: String) {
        guard let comic = db.getComic(id: id), let file = comic.coverFile, !file.isEmpty else {
            throw SourceError("没有封面")
        }
        // 防目录穿越：封面文件名必须等于自身 basename
        let name = (file as NSString).lastPathComponent
        guard name == file, name != ".", name != ".." else {
            throw SourceError("封面路径非法")
        }
        let path = (coversDir as NSString).appendingPathComponent(name)
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let ext = (name as NSString).pathExtension.lowercased()
        return (data, ext == "png" ? "image/png" : "image/jpeg")
    }

    /// 准备一次下载：普通文件直接返回原路径；文件夹打包成临时 zip
    func makeDownload(id: String) throws -> Download {
        guard let comic = db.getComic(id: id) else {
            throw SourceError("漫画不存在，可能已被移除")
        }

        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: comic.sourcePath, isDirectory: &isDirectory) else {
            throw SourceError("来源已丢失：\(comic.title)")
        }

        if isDirectory.boolValue {
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("lan-download-\(UUID().uuidString).zip")
            do {
                try BackupCodec.createZip(
                    ofDirectory: comic.sourcePath,
                    at: tempURL.path,
                    storeOnly: true
                )
            } catch {
                // 打包中途失败：别把半截临时文件留在磁盘里
                try? FileManager.default.removeItem(at: tempURL)
                throw error
            }
            let size = Self.fileSize(tempURL.path)
            let fileName = downloadName(
                preferred: comic.title + ".zip",
                fallbackTitle: comic.title,
                ext: "zip"
            )
            return Download(
                url: tempURL,
                fileName: fileName,
                contentType: "application/zip",
                size: size,
                deleteAfterSend: true
            )
        }

        let ext = (comic.sourcePath as NSString).pathExtension.lowercased()
        let fileName = downloadName(
            preferred: (comic.sourcePath as NSString).lastPathComponent,
            fallbackTitle: comic.title,
            ext: ext
        )
        return Download(
            url: URL(fileURLWithPath: comic.sourcePath),
            fileName: fileName,
            contentType: Self.contentType(for: ext),
            size: Self.fileSize(comic.sourcePath),
            deleteAfterSend: false
        )
    }

    // MARK: 内部

    private func downloadName(preferred: String, fallbackTitle: String, ext: String) -> String {
        if let safe = TransferNaming.sanitizeFileName(preferred) {
            return safe
        }
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        let fallback = fallbackTitle + suffix
        return TransferNaming.sanitizeFileName(fallback) ?? ("comic" + suffix)
    }

    private static func contentType(for ext: String) -> String {
        switch ext {
        case "pdf": return "application/pdf"
        case "zip", "cbz": return "application/zip"
        case "rar", "cbr": return "application/vnd.rar"
        default: return "application/octet-stream"
        }
    }

    private static func fileSize(_ path: String) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
