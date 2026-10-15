import Foundation

// MARK: - library.json 的 schema 迁移管线（src/main/store/migrations.ts 的逐行移植）
//
// 迁移操作在动态 JSON 字典上进行（对应桌面版的 Record<string, unknown>），
// 不经过强类型解码——这样未知字段才能原样保留（与桌面版的展开语义一致）。
//
// 版本历史（与桌面版同步维护）：
//   v1  MVP：{ version, settings, comics }
//   v2  settings 增加 cardSize（书架卡片大小）
//   v3  settings 增加 extensions（扩展开关）、顶层增加 categories（分类集合）、comic 增加 categoryIds
//   v4  comic 增加 bookmarks；settings 增加阅读器增强项（双页封面/跨页、亮度、自动翻页、
//       侧键翻页、自动裁边）与库根目录（libraryRoots / autoScanRoots）；extensions 增加 bookmarks
//   v5  comic 增加 style（类型标签：日漫 / 韩漫 / 国漫 / 美漫）；settings 增加 autoScrollSpeed（条漫平滑滚动速度）

public struct MigrationOutcome: Sendable {
    public var data: [String: Any]
    public var fromVersion: Int
    public var migrated: Bool
}

typealias JSONDict = [String: Any]

/// 每一步只负责 n → n+1，保持小而可测
///
/// 注意：所有「设默认值」都遵循桌面版的合并语义——默认值只补缺，
/// 老数据里已有同名字段时以老数据为准（桌面版是「默认值放前面再展开老数据」，
/// 这里等价地写成「已存在则不动」）。
let MIGRATIONS: [Int: (JSONDict) -> JSONDict] = [
    // 1 → 2
    1: { data in
        var d = data
        var settings = d["settings"] as? JSONDict ?? [:]
        if settings["cardSize"] == nil { settings["cardSize"] = "medium" }
        d["settings"] = settings
        d["version"] = 2
        return d
    },
    // 2 → 3
    2: { data in
        var d = data
        var settings = d["settings"] as? JSONDict ?? [:]
        var extensions = settings["extensions"] as? JSONDict ?? [:]
        if extensions["categories"] == nil { extensions["categories"] = false }
        settings["extensions"] = extensions
        d["settings"] = settings
        if d["categories"] == nil { d["categories"] = [] }
        let comics = d["comics"] as? [Any] ?? []
        d["comics"] = comics.map { c in
            guard let c = c as? JSONDict else { return c }
            var comic = c
            if comic["categoryIds"] == nil { comic["categoryIds"] = [] }
            return comic
        }
        d["version"] = 3
        return d
    },
    // 3 → 4
    3: { data in
        var d = data
        var settings = d["settings"] as? JSONDict ?? [:]
        // v4 新增的设置默认值（老数据已有同名键时不动）
        let defaults: JSONDict = [
            "doubleCoverSingle": true,
            "widePageSpread": true,
            "brightness": 1,
            "autoTurnSeconds": 6,
            "mouseSideButtons": true,
            "autoCrop": false,
            "libraryRoots": [],
            "autoScanRoots": true
        ]
        for (key, value) in defaults where settings[key] == nil {
            settings[key] = value
        }
        // extensions 逐键合并（不能整体覆盖）
        var extensions = settings["extensions"] as? JSONDict ?? [:]
        if extensions["bookmarks"] == nil { extensions["bookmarks"] = false }
        settings["extensions"] = extensions
        d["settings"] = settings
        let comics = d["comics"] as? [Any] ?? []
        d["comics"] = comics.map { c in
            guard let c = c as? JSONDict else { return c }
            var comic = c
            if comic["bookmarks"] == nil { comic["bookmarks"] = [] }
            return comic
        }
        d["version"] = 4
        return d
    },
    // 4 → 5
    4: { data in
        var d = data
        var settings = d["settings"] as? JSONDict ?? [:]
        if settings["autoScrollSpeed"] == nil { settings["autoScrollSpeed"] = 80 }
        d["settings"] = settings
        let comics = d["comics"] as? [Any] ?? []
        d["comics"] = comics
        d["version"] = 5
        return d
    }
]

private func readVersion(_ data: JSONDict) -> Int {
    if let v = data["version"] as? Int, v >= 1 { return v }
    // NSNumber 兼容：JSONSerialization 出来的整数也可能是 Double
    if let v = data["version"] as? Double, v.rounded() == v, v >= 1 { return Int(v) }
    return 1
}

public func migrateLibraryData(_ raw: Any?) -> MigrationOutcome {
    guard let raw = raw as? JSONDict else {
        // 完全无法识别：当作全新数据（调用方的 sanitize 会给出空库）
        return MigrationOutcome(
            data: ["version": CURRENT_SCHEMA_VERSION],
            fromVersion: CURRENT_SCHEMA_VERSION,
            migrated: false
        )
    }

    var data = raw
    let fromVersion = readVersion(data)

    // 来自更新版本的数据（例如用户回退安装了旧版）：
    // 不做降级改写，按已知字段尽力读取，向前兼容交给 sanitize
    if fromVersion > CURRENT_SCHEMA_VERSION {
        return MigrationOutcome(data: data, fromVersion: fromVersion, migrated: false)
    }

    var version = fromVersion
    while version < CURRENT_SCHEMA_VERSION {
        guard let step = MIGRATIONS[version] else { break } // 缺失步骤：停在当前形态，靠 sanitize 兜底
        data = step(data)
        version += 1
    }
    data["version"] = version

    return MigrationOutcome(data: data, fromVersion: fromVersion, migrated: version != fromVersion)
}
