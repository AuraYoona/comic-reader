import Foundation

#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

// MARK: - 备份 / 恢复（src/main/backup.ts 的移植）
//
// 备份格式与桌面版完全互通：
//   备份目录 = library.json（缩进 2，给人看）+ covers/（只含被引用的封面，原名复制）
//   merge   = 只补充书架里没有的来源；分类按名字对齐；漫画一律换新 id
//   replace = 整库替换；替换前自动把当前 library.json 另存为 .pre-restore-<ts>.bak
//
// iOS 交付层（App）把备份目录打成 zip 走分享面板；桌面版导出的备份文件夹
// 由用户自己压成 zip 再导入，同样可用。

public enum BackupCodec {
    static let libraryFileName = "library.json"
    static let coversDirName = "covers"

    // MARK: 命名

    /// "comic-reader-backup-20261016-1530"（本地时间，零填充）
    public static func folderName(now: Double) -> String {
        let date = Date(timeIntervalSince1970: now / 1000)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd-HHmm"
        return "comic-reader-backup-\(fmt.string(from: date))"
    }

    /// 只取文件名，杜绝备份数据里带 ../ 之类的路径穿越
    static func safeCoverName(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        let base = (name as NSString).lastPathComponent
        guard base == name, base != ".", base != ".." else { return nil }
        return base
    }

    // MARK: 导出

    /// 在 parentDir 下创建备份目录；flush 后导出快照与封面
    public static func export(
        db: LibraryDatabase, parentDir: String, coversDir: String, now: Double
    ) -> BackupResult {
        // 退出前的数据也要落盘，保证导出的是最新状态
        db.flushSync()
        let snapshot = db.snapshot()
        let dir = parentDir + "/" + folderName(now: now)
        let fm = FileManager.default
        do {
            try fm.createDirectory(atPath: dir + "/" + coversDirName, withIntermediateDirectories: true)

            // 备份文件是给人看的，这里保留缩进
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let json = try encoder.encode(snapshot)
            try json.write(to: URL(fileURLWithPath: dir + "/" + libraryFileName))

            var covers = 0
            for comic in snapshot.comics {
                guard let name = safeCoverName(comic.coverFile) else { continue }
                if copyFile(from: coversDir, to: dir + "/" + coversDirName, name: name, toName: name) {
                    covers += 1
                }
            }
            return BackupResult(
                canceled: false, ok: true, path: dir,
                comics: snapshot.comics.count, covers: covers
            )
        } catch {
            return BackupResult(
                canceled: false, ok: false,
                error: "导出失败：\(error.localizedDescription)"
            )
        }
    }

    // MARK: 恢复

    /// backupDir 必须含 library.json；merge 或 replace 语义严格对齐桌面版
    public static func restore(
        fromBackupDir dir: String, mode: RestoreMode,
        db: LibraryDatabase, coversDir: String, now: Double
    ) -> RestoreResult {
        let data: LibraryFile
        do {
            data = try readBackup(dir)
        } catch {
            return RestoreResult(
                canceled: false, ok: false,
                error: "这个文件夹里没有可用的 library.json，请选择备份目录本身"
            )
        }

        let coversFrom = dir + "/" + coversDirName
        do {
            switch mode {
            case .merge:
                return try mergeBackup(data, coversFrom: coversFrom, db: db, coversDir: coversDir)
            case .replace:
                return try replaceWithBackup(
                    data, coversFrom: coversFrom, db: db, coversDir: coversDir, now: now
                )
            }
        } catch {
            return RestoreResult(
                canceled: false, ok: false,
                error: "恢复失败：\(error.localizedDescription)"
            )
        }
    }

    private static func readBackup(_ dir: String) throws -> LibraryFile {
        let text = try String(contentsOfFile: dir + "/" + libraryFileName, encoding: .utf8)
        let parsed = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return normalizeLibraryData(parsed).data
    }

    /**
     合并：只补充书架里没有的来源，已存在的原样跳过。
     分类按名称对齐（同名复用本地的），漫画一律换新 id 以免与本地记录撞车。
     */
    private static func mergeBackup(
        _ data: LibraryFile, coversFrom: String, db: LibraryDatabase, coversDir: String
    ) throws -> RestoreResult {
        var categoryIdMap: [String: String] = [:]
        var localByName: [String: ComicCategory] = [:]
        for category in db.listCategories() {
            localByName[category.name] = category
        }
        for cat in data.categories {
            if let local = localByName[cat.name] {
                categoryIdMap[cat.id] = local.id
            } else {
                let created = db.createCategory(name: cat.name, color: cat.color)
                localByName[created.name] = created
                categoryIdMap[cat.id] = created.id
            }
        }

        var known = Set(db.listComics().map { normalizeForCompare($0.sourcePath) })
        try FileManager.default.createDirectory(atPath: coversDir, withIntermediateDirectories: true)

        var imported = 0
        var skipped = 0
        for comic in data.comics {
            let norm = normalizeForCompare(comic.sourcePath)
            if known.contains(norm) {
                skipped += 1
                continue
            }
            known.insert(norm)

            let id = UUID().uuidString.lowercased()
            var coverFile: String? = nil
            if let name = safeCoverName(comic.coverFile) {
                let ext = (name as NSString).pathExtension.lowercased()
                let target = ext.isEmpty ? id : "\(id).\(ext)"
                if copyFile(from: coversFrom, to: coversDir, name: name, toName: target) {
                    coverFile = target
                }
                // 封面丢了不影响记录本身，书架会显示占位图
            }

            var restored = comic
            restored.id = id
            restored.coverFile = coverFile
            restored.categoryIds = comic.categoryIds.compactMap { categoryIdMap[$0] }
            db.upsertComic(restored)
            imported += 1
        }

        return RestoreResult(
            canceled: false, ok: true, mode: .merge, imported: imported, skipped: skipped
        )
    }

    /// 覆盖：整库替换，替换前把当前的 library.json 另存一份
    private static func replaceWithBackup(
        _ data: LibraryFile, coversFrom: String, db: LibraryDatabase, coversDir: String, now: Double
    ) throws -> RestoreResult {
        db.flushSync()
        let libraryPath = db.libraryPath()
        // 覆盖恢复前的自动备份失败也继续
        try? FileManager.default.copyItem(
            atPath: libraryPath, toPath: "\(libraryPath).pre-restore-\(Int(now)).bak"
        )

        try FileManager.default.createDirectory(atPath: coversDir, withIntermediateDirectories: true)
        var wanted = Set<String>()
        var comics = data.comics
        for i in comics.indices {
            guard let name = safeCoverName(comics[i].coverFile) else {
                comics[i].coverFile = nil
                continue
            }
            if copyFile(from: coversFrom, to: coversDir, name: name, toName: name) {
                wanted.insert(name)
            } else {
                comics[i].coverFile = nil
            }
        }

        let restored = LibraryFile(
            version: CURRENT_SCHEMA_VERSION,
            settings: data.settings,
            comics: comics,
            categories: data.categories
        )
        db.replaceAll(restored)

        // 清掉不再被引用的旧封面，避免目录无限膨胀
        if let files = try? FileManager.default.contentsOfDirectory(atPath: coversDir) {
            for file in files where !wanted.contains(file) {
                try? FileManager.default.removeItem(atPath: coversDir + "/" + file)
            }
        }

        return RestoreResult(
            canceled: false, ok: true, mode: .replace, imported: comics.count, skipped: 0
        )
    }

    private static func copyFile(from: String, to: String, name: String, toName: String) -> Bool {
        do {
            try FileManager.default.copyItem(
                atPath: from + "/" + name, toPath: to + "/" + toName
            )
            return true
        } catch {
            return false
        }
    }

    // MARK: zip 打包 / 解包（iOS 交付层用；桌面版没有这层）

    #if canImport(ZIPFoundation)
    /// 把备份目录打成 zip 数据
    public static func zipDirectory(_ dir: String) throws -> Data {
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("backup-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        try createZip(ofDirectory: dir, at: tmpURL.path)
        return try Data(contentsOf: tmpURL)
    }

    /// 把一个目录写成 zip 文件（局域网下载文件夹漫画时直接流式发送临时文件，
    /// 避免把整本漫画读进内存）。storeOnly = true 时只存储不压缩——图片本身
    /// 已经压缩过，deflate 只会白耗 CPU。
    public static func createZip(
        ofDirectory dir: String,
        at destPath: String,
        storeOnly: Bool = false
    ) throws {
        let fm = FileManager.default
        let destURL = URL(fileURLWithPath: destPath)
        if fm.fileExists(atPath: destPath) {
            try? fm.removeItem(at: destURL)
        }

        let archive = try Archive(url: destURL, accessMode: .create)
        // macOS 上 /var 是 /private/var 的符号链接：枚举器返回真实路径，
        // 直接做字符串前缀替换会得到绝对路径（zip 条目非法）——两边都解析符号链接，
        // 再按 pathComponents 计算相对路径
        let root = URL(fileURLWithPath: dir).resolvingSymlinksInPath()
        let rootComponents = root.pathComponents
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            throw SourceError("目录不可读")
        }

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            // 不跟随符号链接：避免把沙盒外/指向目录的链接内容塞进 zip
            guard values.isDirectory != true, values.isSymbolicLink != true else { continue }
            let components = fileURL.resolvingSymlinksInPath().pathComponents
            guard components.count > rootComponents.count else { continue }
            let rel = components.dropFirst(rootComponents.count).joined(separator: "/")
            // 压缩方法由参数类型推导（ZIPFoundation 0.9.19 的类型名是 CompressionMethod，
            // 不要显式写出，避免与系统 Compression 框架歧义）
            try archive.addEntry(with: rel, fileURL: fileURL, compressionMethod: storeOnly ? .none : .deflate)
        }
    }

    /// zip 解包到目标目录（须不存在或为空）；拒绝绝对路径与 .. 穿越
    public static func unzip(_ data: Data, to dir: String) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dir) {
            let contents = try fm.contentsOfDirectory(atPath: dir)
            guard contents.isEmpty else {
                throw SourceError("目标目录不为空，拒绝解包")
            }
        } else {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("backup-\(UUID().uuidString).zip")
        try data.write(to: tmpURL)
        defer { try? fm.removeItem(at: tmpURL) }

        let archive = try Archive(url: tmpURL, accessMode: .read)
        let rootURL = URL(fileURLWithPath: dir)
        for entry in archive {
            let path = entry.path
            // 目录穿越与绝对路径一律拒绝
            guard !path.hasPrefix("/"),
                  !path.split(separator: "/").contains("..") else {
                throw SourceError("压缩包内含非法路径，已拒绝解包")
            }
            guard entry.type == .file else { continue }
            let dest = rootURL.appendingPathComponent(path)
            try fm.createDirectory(
                at: dest.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            _ = try archive.extract(entry, to: dest)
        }
    }
    #endif
}
