import Foundation

// MARK: - 数据净化（src/main/store/db.ts sanitize 函数族的移植）
//
// 任何来源（磁盘 / 备份文件）的数据都先过这里，保证运行时值总是可用。

/// 分类颜色必须是 #rrggbb 形式，非法值回退到预设色
func isValidHexColor(_ s: String) -> Bool {
    var chars = Substring(s)
    guard chars.count == 7, chars.first == "#" else { return false }
    chars = chars.dropFirst()
    return chars.allSatisfy { c in
        (c >= "0" && c <= "9") || (c >= "a" && c <= "f") || (c >= "A" && c <= "F")
    }
}

/// 书签页码归一化：整数、非负、去重、升序
public func sanitizeBookmarks(_ raw: Any?) -> [Int] {
    guard let arr = raw as? [Any] else { return [] }
    var set = Set<Int>()
    for v in arr {
        guard let d = v as? Double, d.isFinite else { continue }
        let n = Int(d.rounded())
        if n >= 0 { set.insert(n) }
    }
    return set.sorted()
}

/// 过滤掉非法设置值（例如手改 JSON 写错枚举），保证运行时值总是可用
func sanitizeSettings(_ raw: Any?) -> AppSettings {
    var s = AppSettings.defaults
    guard let r = raw as? [String: Any] else { return s }

    if let v = r["theme"] as? String, let parsed = ThemeMode(rawValue: v) { s.theme = parsed }
    if let v = r["readingDirection"] as? String, let parsed = ReadingDirection(rawValue: v) {
        s.readingDirection = parsed
    }
    if let v = r["defaultMode"] as? String, let parsed = ReadingMode(rawValue: v) {
        s.defaultMode = parsed
    }
    if let v = r["defaultZoom"] as? String, let parsed = ZoomMode(rawValue: v) {
        s.defaultZoom = parsed
    }
    if let v = r["openLastOnStartup"] as? Bool { s.openLastOnStartup = v }
    if let v = r["lastOpenedComicId"] as? String { s.lastOpenedComicId = v }
    if let v = r["cardSize"] as? String, let parsed = CardSize(rawValue: v) { s.cardSize = parsed }
    if let v = r["autoCheckUpdates"] as? Bool { s.autoCheckUpdates = v }
    if let v = r["doubleCoverSingle"] as? Bool { s.doubleCoverSingle = v }
    if let v = r["widePageSpread"] as? Bool { s.widePageSpread = v }
    if let v = r["brightness"] as? Double { s.brightness = BrightnessLimits.clamp(v) }
    if let v = r["autoTurnSeconds"] as? Double {
        s.autoTurnSeconds = AutoTurnLimits.clamp(Int(v))
    }
    if let v = r["mouseSideButtons"] as? Bool { s.mouseSideButtons = v }
    if let v = r["autoCrop"] as? Bool { s.autoCrop = v }
    if let v = r["autoScanRoots"] as? Bool { s.autoScanRoots = v }
    if let v = r["autoScrollSpeed"] as? Double { s.autoScrollSpeed = AutoScrollLimits.clamp(v) }
    if let arr = r["libraryRoots"] as? [Any] {
        var seen = Set<String>()
        var roots: [String] = []
        for item in arr {
            guard let item = item as? String, !item.trimmingCharacters(in: .whitespaces).isEmpty
            else { continue }
            // iOS 文件系统默认大小写不敏感，统一按小写去重
            let key = item.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            roots.append(item)
            if roots.count >= Limits.libraryRootsMax { break }
        }
        s.libraryRoots = roots
    }
    if let ext = r["extensions"] as? [String: Any] {
        // 只认白名单里的扩展 ID，且值必须是布尔
        for id in ExtensionId.allCases {
            if let v = ext[id.rawValue] as? Bool {
                switch id {
                case .categories: s.extensions.categories = v
                case .bookmarks: s.extensions.bookmarks = v
                }
            }
        }
    }
    return s
}

/// 类型标签只认白名单，其余（含旧版写入的未知值）一律视为未打标签
public func sanitizeStyle(_ raw: Any?) -> ComicStyle? {
    guard let s = raw as? String else { return nil }
    return ComicStyle(rawValue: s)
}

func sanitizeComics(_ raw: Any?) -> [Comic] {
    guard let arr = raw as? [Any] else { return [] }
    var out: [Comic] = []
    for item in arr {
        guard let c = item as? [String: Any],
              let id = c["id"] as? String,
              let sourcePath = c["sourcePath"] as? String,
              let title = c["title"] as? String
        else { continue }
        // 其余字段走 Codable 的 decodeIfPresent 默认值兜底
        let data = try? JSONSerialization.data(withJSONObject: c)
        var comic = data.flatMap {
            try? JSONDecoder().decode(Comic.self, from: $0)
        } ?? Comic(
            id: id, title: title, sourceType: .archive, sourcePath: sourcePath,
            pageCount: 0, addedAt: 0
        )
        comic.id = id
        comic.title = title
        comic.sourcePath = sourcePath
        comic.categoryIds = (c["categoryIds"] as? [Any])?.compactMap { $0 as? String } ?? []
        comic.bookmarks = sanitizeBookmarks(c["bookmarks"])
        comic.style = sanitizeStyle(c["style"])
        out.append(comic)
    }
    return out
}

/// 过滤非法分类记录：id/name 必须是字符串且 name 去空白后非空，按 id 去重
func sanitizeCategories(_ raw: Any?, now: Double = 0) -> [ComicCategory] {
    guard let arr = raw as? [Any] else { return [] }
    var out: [ComicCategory] = []
    var seen = Set<String>()
    for item in arr {
        guard let r = item as? [String: Any],
              let id = r["id"] as? String,
              let nameRaw = r["name"] as? String
        else { continue }
        let name = nameRaw.trimmingCharacters(in: .whitespaces)
        if name.isEmpty || seen.contains(id) { continue }
        seen.insert(id)
        let color: String
        if let c = r["color"] as? String, isValidHexColor(c) {
            color = c
        } else {
            color = Limits.categoryColors[out.count % Limits.categoryColors.count]
        }
        let createdAt = (r["createdAt"] as? Double) ?? now
        out.append(ComicCategory(id: id, name: name, color: color, createdAt: createdAt))
    }
    return out
}

public struct NormalizedLibrary: Sendable {
    public var data: LibraryFile
    public var fromVersion: Int
    public var migrated: Bool
}

/// 把一份任意来源的数据（磁盘文件 / 备份文件）迁移并清洗成可用的库结构
public func normalizeLibraryData(_ parsed: Any?, now: Double = 0) -> NormalizedLibrary {
    let outcome = migrateLibraryData(parsed)
    let settings = sanitizeSettings(outcome.data["settings"])
    var comics = sanitizeComics(outcome.data["comics"])
    let categories = sanitizeCategories(outcome.data["categories"], now: now)
    // 分类记录可能在上面被过滤掉，同步剥离漫画里指向它们的悬空 id
    let knownIds = Set(categories.map(\.id))
    for i in comics.indices {
        comics[i].categoryIds = comics[i].categoryIds.filter { knownIds.contains($0) }
    }
    return NormalizedLibrary(
        data: LibraryFile(
            version: CURRENT_SCHEMA_VERSION,
            settings: settings,
            comics: comics,
            categories: categories
        ),
        fromVersion: outcome.fromVersion,
        migrated: outcome.migrated
    )
}
