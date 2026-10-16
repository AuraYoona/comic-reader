import Foundation
import UIKit
import ComicReaderCore

// MARK: - 封面存取（src/main/importer.ts generateCover / regenerateCover + ipc.ts cover:save-thumb 的移植）
//
// 命名约定与桌面版一致：
//   - 导入时生成：      <uuid>.jpg        （covers.ts：.jpg = 已生成缩略图）
//   - 重新生成/重压：   <comicId>-<ts>.jpg（时间戳做缓存失效标记）
// iOS 上 ImageIO 全能解码，单阶段生成，无需桌面版的「原图直存 + 渲染进程重压」两段式。

@MainActor
final class CoverStore: ObservableObject {
    private let coversDir: String
    /// 已解码封面（按文件名缓存；封面重生成换新文件名，天然失效）
    private let cache = NSCache<NSString, UIImage>()

    init(coversDir: String) {
        self.coversDir = coversDir
        cache.countLimit = 256
    }

    func url(for comic: Comic) -> URL? {
        guard let file = comic.coverFile, !file.isEmpty else { return nil }
        // 防目录穿越：文件名必须等于自身 basename 且非 "."/".."
        let name = (file as NSString).lastPathComponent
        guard name == file, name != ".", name != ".." else { return nil }
        return URL(fileURLWithPath: coversDir).appendingPathComponent(name)
    }

    func image(for comic: Comic) -> UIImage? {
        guard let file = comic.coverFile, !file.isEmpty else { return nil }
        if let hit = cache.object(forKey: file as NSString) { return hit }
        guard let url = url(for: comic), FileManager.default.fileExists(atPath: url.path),
              let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        cache.setObject(image, forKey: file as NSString)
        return image
    }

    /// 封面文件是否存在（来源丢失/封面缺失时显示占位）
    func hasCover(for comic: Comic) -> Bool {
        guard let url = url(for: comic) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// 写入导入时生成的封面，返回文件名（失败返回 nil）
    func saveImportedCover(_ jpeg: Data) -> String? {
        let name = "\(UUID().uuidString.lowercased()).jpg"
        return write(jpeg, name: name) ? name : nil
    }

    /// 重新生成封面：读第一页 → 480px JPEG → 时间戳命名；更新数据库
    /// （对应桌面版 regenerateCover；旧封面文件删除）
    @discardableResult
    func regenerateCover(for comic: Comic, db: LibraryDatabase, now: Double) -> Comic? {
        guard let page = try? readPage(comic, index: 0),
              let jpeg = ImagePipeline.makeCover(from: page.data) else {
            return nil
        }
        let old = comic.coverFile
        let name = "\(comic.id)-\(Int(now)).jpg"
        guard write(jpeg, name: name) else { return nil }
        let updated = db.setCoverFile(id: comic.id, coverFile: name)
        if let old, old != name {
            removeCoverFile(old)
        }
        return updated
    }

    /// 删除某个封面文件（移除漫画记录时用；文件不存在则忽略）
    func removeCoverFile(_ file: String?) {
        guard let file, !file.isEmpty else { return }
        let name = (file as NSString).lastPathComponent
        guard name == file, name != ".", name != ".." else { return }
        let path = (coversDir as NSString).appendingPathComponent(name)
        try? FileManager.default.removeItem(atPath: path)
    }

    private func write(_ data: Data, name: String) -> Bool {
        let path = (coversDir as NSString).appendingPathComponent(name)
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }
}
