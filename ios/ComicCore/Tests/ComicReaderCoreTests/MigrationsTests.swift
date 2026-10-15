import XCTest
@testable import ComicReaderCore

// tests/unit/migrations.test.ts 的移植

final class MigrationsTests: XCTestCase {
    private func settings(_ data: [String: Any]) -> [String: Any] {
        data["settings"] as? [String: Any] ?? [:]
    }

    private func comics(_ data: [String: Any]) -> [[String: Any]] {
        (data["comics"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    func testV1toV2AddsCardSizeAndPreservesFields() {
        let v1: [String: Any] = [
            "version": 1,
            "settings": ["theme": "dark", "readingDirection": "rtl"],
            "comics": [["id": "a", "title": "A", "sourcePath": "C:/a"]]
        ]
        let outcome = migrateLibraryData(v1)
        XCTAssertTrue(outcome.migrated)
        XCTAssertEqual(outcome.fromVersion, 1)
        XCTAssertEqual(outcome.data["version"] as? Int, CURRENT_SCHEMA_VERSION)
        let s = settings(outcome.data)
        XCTAssertEqual(s["cardSize"] as? String, "medium")
        XCTAssertEqual(s["theme"] as? String, "dark")
        XCTAssertEqual(s["readingDirection"] as? String, "rtl")
        // v2 之后的迁移步骤会补充新字段（如 categoryIds），原有字段仍须原样保留
        let migratedComic = comics(outcome.data)[0]
        XCTAssertEqual(migratedComic["id"] as? String, "a")
        XCTAssertEqual(migratedComic["title"] as? String, "A")
        XCTAssertEqual(migratedComic["sourcePath"] as? String, "C:/a")
    }

    func testCurrentVersionNotMigrated() {
        let now: [String: Any] = [
            "version": CURRENT_SCHEMA_VERSION,
            "settings": ["cardSize": "large"],
            "comics": [] as [[String: Any]]
        ]
        let outcome = migrateLibraryData(now)
        XCTAssertFalse(outcome.migrated)
        XCTAssertEqual(settings(outcome.data)["cardSize"] as? String, "large")
    }

    func testExistingFieldsWinOverDefaults() {
        let v1: [String: Any] = [
            "version": 1,
            "settings": ["cardSize": "small"],
            "comics": [] as [[String: Any]]
        ]
        let outcome = migrateLibraryData(v1)
        XCTAssertEqual(settings(outcome.data)["cardSize"] as? String, "small")
    }

    func testV2toV3AddsExtensionsCategoriesCategoryIds() {
        let v2: [String: Any] = [
            "version": 2,
            "settings": ["theme": "dark", "cardSize": "large"],
            "comics": [
                ["id": "a", "title": "A", "sourcePath": "C:/a"],
                ["id": "b", "title": "B", "sourcePath": "C:/b"]
            ] as [[String: Any]]
        ]
        let outcome = migrateLibraryData(v2)
        XCTAssertTrue(outcome.migrated)
        XCTAssertEqual(outcome.fromVersion, 2)
        XCTAssertEqual(outcome.data["version"] as? Int, CURRENT_SCHEMA_VERSION)
        let s = settings(outcome.data)
        let ext = s["extensions"] as? [String: Any]
        XCTAssertEqual(ext?["categories"] as? Bool, false)
        XCTAssertEqual(ext?["bookmarks"] as? Bool, false)
        XCTAssertEqual(s["theme"] as? String, "dark")
        XCTAssertEqual(s["cardSize"] as? String, "large")
        XCTAssertEqual((outcome.data["categories"] as? [Any])?.count, 0)
        for c in comics(outcome.data) {
            XCTAssertEqual((c["categoryIds"] as? [Any])?.count, 0)
        }
    }

    func testV2ExistingExtensionCategoriesCategoryIdsPreserved() {
        let v2: [String: Any] = [
            "version": 2,
            "settings": ["cardSize": "medium", "extensions": ["categories": true] as [String: Any]],
            "categories": [["id": "c1", "name": "连载中", "color": "#ef4444", "createdAt": 1]] as [[String: Any]],
            "comics": [["id": "a", "title": "A", "sourcePath": "C:/a", "categoryIds": ["x"]] as [String: Any]]
        ]
        let outcome = migrateLibraryData(v2)
        XCTAssertTrue(outcome.migrated)
        // v4 只往 extensions 里补自己新增的键，老开关保持原值
        let ext = settings(outcome.data)["extensions"] as? [String: Any]
        XCTAssertEqual(ext?["categories"] as? Bool, true)
        XCTAssertEqual(ext?["bookmarks"] as? Bool, false)
        let cats = (outcome.data["categories"] as? [[String: Any]]) ?? []
        XCTAssertEqual(cats[0]["id"] as? String, "c1")
        XCTAssertEqual(comics(outcome.data)[0]["categoryIds"] as? [String], ["x"])
    }

    func testV1ChainToV3() {
        let v1: [String: Any] = [
            "version": 1,
            "settings": ["theme": "dark"],
            "comics": [["id": "a", "title": "A", "sourcePath": "C:/a"]]
        ]
        let outcome = migrateLibraryData(v1)
        XCTAssertTrue(outcome.migrated)
        XCTAssertEqual(outcome.fromVersion, 1)
        XCTAssertEqual(outcome.data["version"] as? Int, CURRENT_SCHEMA_VERSION)
        let s = settings(outcome.data)
        XCTAssertEqual(s["theme"] as? String, "dark")
        XCTAssertEqual(s["cardSize"] as? String, "medium")
        let ext = s["extensions"] as? [String: Any]
        XCTAssertEqual(ext?["categories"] as? Bool, false)
        XCTAssertEqual(ext?["bookmarks"] as? Bool, false)
        XCTAssertEqual((outcome.data["categories"] as? [Any])?.count, 0)
        XCTAssertEqual((comics(outcome.data)[0]["categoryIds"] as? [Any])?.count, 0)
    }

    func testMissingVersionTreatedAsV1() {
        let outcome = migrateLibraryData(["settings": [:] as [String: Any], "comics": [] as [[String: Any]]])
        XCTAssertEqual(outcome.fromVersion, 1)
        XCTAssertTrue(outcome.migrated)
        XCTAssertEqual(outcome.data["version"] as? Int, CURRENT_SCHEMA_VERSION)
    }

    func testV3toV4AddsReaderEnhancementsAndBookmarks() {
        let v3: [String: Any] = [
            "version": 3,
            "settings": [
                "theme": "dark", "cardSize": "large",
                "extensions": ["categories": true] as [String: Any]
            ] as [String: Any],
            "categories": [["id": "c1", "name": "连载中", "color": "#ef4444", "createdAt": 1]] as [[String: Any]],
            "comics": [
                ["id": "a", "title": "A", "sourcePath": "C:/a", "categoryIds": ["c1"]],
                ["id": "b", "title": "B", "sourcePath": "C:/b", "categoryIds": []]
            ] as [[String: Any]]
        ]
        let outcome = migrateLibraryData(v3)
        XCTAssertTrue(outcome.migrated)
        XCTAssertEqual(outcome.fromVersion, 3)
        XCTAssertEqual(outcome.data["version"] as? Int, CURRENT_SCHEMA_VERSION)

        let s = settings(outcome.data)
        XCTAssertEqual(s["doubleCoverSingle"] as? Bool, true)
        XCTAssertEqual(s["widePageSpread"] as? Bool, true)
        XCTAssertEqual(s["brightness"] as? Double ?? 0, 1)
        XCTAssertEqual(s["autoTurnSeconds"] as? Int, 6)
        XCTAssertEqual(s["mouseSideButtons"] as? Bool, true)
        XCTAssertEqual(s["autoCrop"] as? Bool, false)
        XCTAssertEqual((s["libraryRoots"] as? [Any])?.count, 0)
        XCTAssertEqual(s["autoScanRoots"] as? Bool, true)
        // 老字段原样保留
        XCTAssertEqual(s["theme"] as? String, "dark")
        XCTAssertEqual(s["cardSize"] as? String, "large")
        // extensions 逐键合并，不能把已有的 categories 开关冲掉
        let ext = s["extensions"] as? [String: Any]
        XCTAssertEqual(ext?["categories"] as? Bool, true)
        XCTAssertEqual(ext?["bookmarks"] as? Bool, false)

        let cats = (outcome.data["categories"] as? [[String: Any]]) ?? []
        XCTAssertEqual(cats[0]["id"] as? String, "c1")
        for c in comics(outcome.data) {
            XCTAssertEqual((c["bookmarks"] as? [Any])?.count, 0)
        }
        XCTAssertEqual(comics(outcome.data)[0]["categoryIds"] as? [String], ["c1"])
    }

    func testV3ExistingV4FieldsPreserved() {
        let v3: [String: Any] = [
            "version": 3,
            "settings": [
                "brightness": 0.6,
                "autoScanRoots": false,
                "libraryRoots": ["D:/comics"],
                "extensions": ["categories": false, "bookmarks": true] as [String: Any]
            ] as [String: Any],
            "comics": [["id": "a", "title": "A", "sourcePath": "C:/a", "bookmarks": [3, 7]] as [String: Any]]
        ]
        let outcome = migrateLibraryData(v3)
        let s = settings(outcome.data)
        XCTAssertEqual(s["brightness"] as? Double, 0.6)
        XCTAssertEqual(s["autoScanRoots"] as? Bool, false)
        XCTAssertEqual(s["libraryRoots"] as? [String], ["D:/comics"])
        let ext = s["extensions"] as? [String: Any]
        XCTAssertEqual(ext?["categories"] as? Bool, false)
        XCTAssertEqual(ext?["bookmarks"] as? Bool, true)
        XCTAssertEqual(comics(outcome.data)[0]["bookmarks"] as? [Int], [3, 7])
    }

    func testV4toV5AddsAutoScrollSpeedAndStyle() {
        let v4: [String: Any] = [
            "version": 4,
            "settings": ["theme": "dark"],
            "categories": [] as [[String: Any]],
            "comics": [
                ["id": "a", "title": "A", "sourcePath": "C:/a", "categoryIds": [], "bookmarks": []] as [String: Any],
                ["id": "b", "title": "B", "sourcePath": "C:/b", "categoryIds": [], "bookmarks": [], "style": "manga"] as [String: Any]
            ]
        ]
        let outcome = migrateLibraryData(v4)
        XCTAssertTrue(outcome.migrated)
        XCTAssertEqual(outcome.fromVersion, 4)
        XCTAssertEqual(outcome.data["version"] as? Int, 5)
        let s = settings(outcome.data)
        XCTAssertEqual(s["theme"] as? String, "dark")
        XCTAssertEqual(s["autoScrollSpeed"] as? Int, 80)
        let cs = comics(outcome.data)
        XCTAssertNil(cs[0]["style"])
        XCTAssertEqual(cs[1]["style"] as? String, "manga")
    }

    func testV1ChainToV5FillsAllFields() {
        let v1: [String: Any] = [
            "version": 1,
            "settings": ["theme": "light"],
            "comics": [["id": "a", "title": "A", "sourcePath": "C:/a"]]
        ]
        let outcome = migrateLibraryData(v1)
        XCTAssertTrue(outcome.migrated)
        let s = settings(outcome.data)
        XCTAssertEqual(s["theme"] as? String, "light")
        XCTAssertEqual(s["cardSize"] as? String, "medium")
        let ext = s["extensions"] as? [String: Any]
        XCTAssertEqual(ext?["categories"] as? Bool, false)
        XCTAssertEqual(ext?["bookmarks"] as? Bool, false)
        XCTAssertEqual(s["autoScanRoots"] as? Bool, true)
        XCTAssertEqual(s["autoScrollSpeed"] as? Int, 80)
        let comic = comics(outcome.data)[0]
        XCTAssertEqual((comic["categoryIds"] as? [Any])?.count, 0)
        XCTAssertEqual((comic["bookmarks"] as? [Any])?.count, 0)
        // style 缺省 = nil（未补字段）
        XCTAssertNil(comic["style"])
    }

    func testFutureVersionPassedThrough() {
        let future: [String: Any] = [
            "version": CURRENT_SCHEMA_VERSION + 5,
            "settings": [:] as [String: Any],
            "comics": [] as [[String: Any]],
            "extra": 1
        ]
        let outcome = migrateLibraryData(future)
        XCTAssertFalse(outcome.migrated)
        XCTAssertEqual(outcome.fromVersion, CURRENT_SCHEMA_VERSION + 5)
        XCTAssertEqual(outcome.data["version"] as? Int, CURRENT_SCHEMA_VERSION + 5)
        XCTAssertEqual(outcome.data["extra"] as? Int, 1)
    }

    func testUnrecognizableInputYieldsFreshCurrentVersion() {
        let junk: [Any?] = [nil, 42, "x", [1, 2]]
        for item in junk {
            let outcome = migrateLibraryData(item)
            XCTAssertFalse(outcome.migrated)
            XCTAssertEqual(outcome.data["version"] as? Int, CURRENT_SCHEMA_VERSION)
        }
    }
}
