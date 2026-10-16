import XCTest
@testable import ComicReaderCore

// LibraryDatabase 的加载恢复 / mutation 语义 / 落盘行为（对照 db.ts）

final class LibraryDatabaseTests: XCTestCase {
    private var root: String!
    private var paths: AppPaths!
    private var manual: ManualClock!

    override func setUp() {
        super.setUp()
        root = NSTemporaryDirectory() + "/db-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: root + "/support", withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: root + "/comics", withIntermediateDirectories: true)
        paths = AppPaths(supportDir: root + "/support", comicsDir: root + "/comics")
        manual = ManualClock()
    }

    override func tearDown() {
        if let root { try? FileManager.default.removeItem(atPath: root) }
        super.tearDown()
    }

    private func makeDB() -> LibraryDatabase {
        let db = LibraryDatabase(paths: paths, clock: manual.clock, now: { [weak manual] in manual?.currentTime ?? 0 })
        return db
    }

    private func writeLibraryFile(_ text: String) {
        try? text.write(toFile: paths.libraryPath, atomically: true, encoding: .utf8)
    }

    private func sampleComic(id: String = "c1") -> Comic {
        Comic(id: id, title: "标题", sourceType: .archive, sourcePath: "/x/\(id).cbz", pageCount: 10, addedAt: 1000)
    }

    // MARK: 加载

    func testLoadMissingFileGivesEmptyLibrary() {
        let db = makeDB()
        db.load()
        XCTAssertTrue(db.listComics().isEmpty)
        XCTAssertEqual(db.getSettings().theme, .system)
    }

    func testCorruptFileBackedUpAndStartsEmpty() {
        writeLibraryFile("{ this is not json")
        let db = makeDB()
        db.load()
        XCTAssertTrue(db.listComics().isEmpty)
        let backups = (try? FileManager.default.contentsOfDirectory(atPath: paths.supportDir))?
            .filter { $0.contains(".corrupt-") } ?? []
        XCTAssertEqual(backups.count, 1, "损坏文件应被备份")
    }

    func testMigrationBacksUpOriginalAndPersists() {
        writeLibraryFile(#"{"version":1,"settings":{"theme":"dark"},"comics":[{"id":"a","title":"A","sourcePath":"/a.cbz"}]}"#)
        let db = makeDB()
        db.load()

        // 迁移备份保留最早那份原文
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.libraryPath + ".v1.bak"))
        // 迁移后数据可用
        XCTAssertEqual(db.getSettings().theme, .dark)
        XCTAssertEqual(db.listComics().count, 1)
        // 迁移结果立即落盘为 v5
        let saved = try? String(contentsOfFile: paths.libraryPath, encoding: .utf8)
        XCTAssertTrue(saved?.contains("\"version\":5") ?? false)
        XCTAssertTrue(saved?.contains("autoScrollSpeed") ?? false)
    }

    func testFutureVersionBackedUpOnce() {
        writeLibraryFile(#"{"version":9,"settings":{"theme":"light"},"comics":[],"categories":[]}"#)
        let db = makeDB()
        db.load()
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.libraryPath + ".v9.bak"))
        XCTAssertEqual(db.getSettings().theme, .light)
    }

    // MARK: 漫画 mutation

    func testUpsertAndDebouncedWrite() {
        let db = makeDB()
        db.load()
        db.upsertComic(sampleComic())
        XCTAssertEqual(db.listComics().count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.libraryPath), "防抖期内不落盘")
        manual.advance(by: 0.41)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.libraryPath))
    }

    func testUpdateProgressMergesReaderPrefsAndClampsPage() {
        let db = makeDB()
        db.load()
        var comic = sampleComic()
        comic.reader = ComicReaderPrefs(mode: .single, direction: .rtl)
        db.upsertComic(comic)

        let updated = db.updateProgress(
            id: "c1",
            patch: ProgressPatch(lastReadPage: 999, reader: ComicReaderPrefs(autoScroll: true))
        )
        XCTAssertEqual(updated?.lastReadPage, 9, "页码应被夹到 pageCount-1")
        XCTAssertEqual(updated?.reader.mode, .single, "部分补丁不得擦掉其他偏好")
        XCTAssertEqual(updated?.reader.direction, .rtl)
        XCTAssertEqual(updated?.reader.autoScroll, true)
        XCTAssertEqual(updated?.lastReadAt, 0)
    }

    func testRemoveComicsClearsLastOpened() {
        let db = makeDB()
        db.load()
        db.upsertComic(sampleComic(id: "a"))
        db.upsertComic(sampleComic(id: "b"))
        db.saveSettings { $0.lastOpenedComicId = "a" }

        let removed = db.removeComics(["a", "missing"])
        XCTAssertEqual(removed, ["a"])
        XCTAssertNil(db.getSettings().lastOpenedComicId)
        XCTAssertEqual(db.listComics().map(\.id), ["b"])
    }

    func testRenameTrimsAndClamps() {
        let db = makeDB()
        db.load()
        db.upsertComic(sampleComic())
        let long = String(repeating: "长", count: 200)
        let renamed = db.renameComic(id: "c1", title: "  \(long)  ")
        XCTAssertEqual(renamed?.title.count, 120)
    }

    func testToggleBookmarkAddsSortedRemoves() {
        let db = makeDB()
        db.load()
        db.upsertComic(sampleComic())
        _ = db.toggleBookmark(id: "c1", page: 5)
        _ = db.toggleBookmark(id: "c1", page: 1)
        XCTAssertEqual(db.getComic(id: "c1")?.bookmarks, [1, 5])
        _ = db.toggleBookmark(id: "c1", page: 5)
        XCTAssertEqual(db.getComic(id: "c1")?.bookmarks, [1])
    }

    func testSetPageCountClampsProgressAndDropsBookmarks() {
        let db = makeDB()
        db.load()
        db.upsertComic(sampleComic())
        _ = db.updateProgress(id: "c1", patch: ProgressPatch(lastReadPage: 9))
        _ = db.toggleBookmark(id: "c1", page: 8)

        let updated = db.setPageCount(id: "c1", pageCount: 3)
        XCTAssertEqual(updated?.lastReadPage, 2)
        XCTAssertEqual(updated?.bookmarks, [])
    }

    func testSetComicsStyleWritesPresetAndUntagKeepsPrefs() {
        let db = makeDB()
        db.load()
        db.upsertComic(sampleComic(id: "a"))
        db.upsertComic(sampleComic(id: "b"))

        let changed = db.setComicsStyle(["a"], style: .manga)
        XCTAssertEqual(changed.count, 1)
        let a = db.getComic(id: "a")
        XCTAssertEqual(a?.style, .manga)
        XCTAssertEqual(a?.reader.direction, .rtl)
        XCTAssertEqual(a?.reader.mode, .single)

        // 摘标签：偏好保持原样
        _ = db.setComicsStyle(["a"], style: nil)
        let untagged = db.getComic(id: "a")
        XCTAssertNil(untagged?.style)
        XCTAssertEqual(untagged?.reader.direction, .rtl, "摘标签不得清掉已写入的偏好")

        // 未变化的记录不重复返回
        XCTAssertEqual(db.setComicsStyle(["b"], style: nil).count, 0)
    }

    // MARK: 设置

    func testSaveSettingsSanitizes() {
        let db = makeDB()
        db.load()
        db.saveSettings {
            $0.brightness = 5       // 超上限
            $0.autoScrollSpeed = 83 // 步进取整
            $0.theme = .dark
        }
        let s = db.getSettings()
        XCTAssertEqual(s.brightness, 1.2)
        XCTAssertEqual(s.autoScrollSpeed, 80)
        XCTAssertEqual(s.theme, .dark)
    }

    func testAddLibraryRootDedupesCaseInsensitively() {
        let db = makeDB()
        db.load()
        _ = db.addLibraryRoot("/Comics/A")
        _ = db.addLibraryRoot("/comics/a")
        XCTAssertEqual(db.getSettings().libraryRoots, ["/Comics/A"])
    }

    // MARK: 分类

    func testCategoryCRUDAndUnlink() {
        let db = makeDB()
        db.load()
        let cat = db.createCategory(name: "连载中")
        XCTAssertEqual(cat.color, "#ef4444", "首个分类取调色板第一色")

        var comic = sampleComic()
        comic.categoryIds = [cat.id]
        db.upsertComic(comic)

        // 重命名 + 换色（非法色被忽略）
        let renamed = db.updateCategory(id: cat.id, patch: CategoryPatch(name: "  已完结  ", color: "not-a-color"))
        XCTAssertEqual(renamed?.name, "已完结")
        XCTAssertEqual(renamed?.color, "#ef4444")
        _ = db.updateCategory(id: cat.id, patch: CategoryPatch(color: "#22c55e"))

        // toggle 方向由数据库当前归属决定
        _ = db.toggleComicCategory(id: "c1", categoryId: cat.id)
        XCTAssertEqual(db.getComic(id: "c1")?.categoryIds, [])
        _ = db.toggleComicCategory(id: "c1", categoryId: cat.id)
        XCTAssertEqual(db.getComic(id: "c1")?.categoryIds, [cat.id])

        // 删除分类只解关联
        XCTAssertTrue(db.deleteCategory(id: cat.id))
        XCTAssertEqual(db.getComic(id: "c1")?.categoryIds, [])
        XCTAssertEqual(db.getComic(id: "c1")?.title, "标题", "漫画记录本身不受影响")
        XCTAssertFalse(db.deleteCategory(id: "missing"))
    }

    func testSetComicsCategoryBulk() {
        let db = makeDB()
        db.load()
        let cat = db.createCategory(name: "X")
        db.upsertComic(sampleComic(id: "a"))
        db.upsertComic(sampleComic(id: "b"))

        let added = db.setComicsCategory(["a", "b"], categoryId: cat.id, add: true)
        XCTAssertEqual(added.count, 2)
        // 幂等：已在其中，再 add 不产生变化
        XCTAssertEqual(db.setComicsCategory(["a"], categoryId: cat.id, add: true).count, 0)
        let removed = db.setComicsCategory(["a"], categoryId: cat.id, add: false)
        XCTAssertEqual(removed.count, 1)
        // 不存在的分类不做任何事
        XCTAssertEqual(db.setComicsCategory(["b"], categoryId: "missing", add: true).count, 0)
    }

    // MARK: 备份 / 恢复

    func testSnapshotIsDeepCopyAndReplaceAllFlushes() {
        let db = makeDB()
        db.load()
        db.upsertComic(sampleComic())
        let snap = db.snapshot()
        XCTAssertEqual(snap.comics.count, 1)

        let empty = LibraryFile(version: CURRENT_SCHEMA_VERSION)
        db.replaceAll(empty)
        XCTAssertTrue(db.listComics().isEmpty)
        // 立即落盘
        let saved = try? String(contentsOfFile: paths.libraryPath, encoding: .utf8)
        XCTAssertNotNil(saved)

        // 旧快照不受影响（值语义）
        XCTAssertEqual(snap.comics.count, 1)
    }

    func testFlushSyncPersistsPendingChanges() {
        let db = makeDB()
        db.load()
        db.upsertComic(sampleComic())
        db.flushSync()
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.libraryPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.libraryPath + ".tmp"), "临时文件应已改名")
    }
}
