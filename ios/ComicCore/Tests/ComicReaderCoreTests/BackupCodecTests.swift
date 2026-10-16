import XCTest
@testable import ComicReaderCore

// BackupCodec 的导出 / 合并 / 覆盖 / zip 往返（对照 src/main/backup.ts）

final class BackupCodecTests: XCTestCase {
    private var root: String!
    private var supportDir: String!
    private var coversDir: String!
    private var comicsDir: String!
    private var manual: ManualClock!

    override func setUp() {
        super.setUp()
        root = NSTemporaryDirectory() + "/backup-test-\(UUID().uuidString)"
        supportDir = root + "/support"
        coversDir = supportDir + "/covers"
        comicsDir = root + "/comics"
        for dir in [supportDir!, coversDir!, comicsDir!] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        manual = ManualClock()
    }

    override func tearDown() {
        if let root { try? FileManager.default.removeItem(atPath: root) }
        super.tearDown()
    }

    private func makeDB() -> LibraryDatabase {
        let db = LibraryDatabase(
            paths: AppPaths(supportDir: supportDir, comicsDir: comicsDir),
            clock: manual.clock,
            now: { [weak manual] in manual?.currentTime ?? 0 }
        )
        return db
    }

    private func write(_ text: String, _ path: String) {
        FileManager.default.createFile(atPath: path, contents: Data(text.utf8))
    }

    private func sampleComic(id: String, source: String, cover: String? = nil, categories: [String] = []) -> Comic {
        Comic(
            id: id, title: "标题-\(id)", sourceType: .archive, sourcePath: source,
            pageCount: 5, coverFile: cover, addedAt: 1000, lastReadAt: nil, lastReadPage: 2,
            reader: ComicReaderPrefs(mode: .single, direction: .rtl),
            categoryIds: categories, bookmarks: [1], style: .manga
        )
    }

    // MARK: 导出

    func testExportWritesLibraryAndReferencedCovers() {
        let db = makeDB()
        db.load()
        let cat = db.createCategory(name: "连载中")
        write("jpeg-bytes", coversDir + "/cover-a.jpg")
        db.upsertComic(sampleComic(id: "a", source: "/lib/a.cbz", cover: "cover-a.jpg", categories: [cat.id]))
        db.upsertComic(sampleComic(id: "b", source: "/lib/b.cbz"))
        // 无主封面不该被导出
        write("orphan", coversDir + "/orphan.jpg")

        let out = BackupCodec.export(db: db, parentDir: root, coversDir: coversDir, now: 0)
        XCTAssertTrue(out.ok)
        XCTAssertEqual(out.comics, 2)
        XCTAssertEqual(out.covers, 1)
        guard let dir = out.path else { return XCTFail("缺少备份目录") }
        XCTAssertTrue(dir.hasSuffix("comic-reader-backup-"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir + "/library.json"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir + "/covers/cover-a.jpg"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir + "/covers/orphan.jpg"))

        let text = try? String(contentsOfFile: dir + "/library.json", encoding: .utf8)
        let parsed = text.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String: Any]
        XCTAssertEqual(parsed?["version"] as? Int, CURRENT_SCHEMA_VERSION)
    }

    func testFolderNameStampFormat() {
        // 2026-10-16 15:30 本地时间 → 20261016-1530
        var comps = DateComponents()
        comps.year = 2026; comps.month = 10; comps.day = 16
        comps.hour = 15; comps.minute = 30
        comps.timeZone = TimeZone.current
        let date = Calendar.current.date(from: comps)!
        let name = BackupCodec.folderName(now: date.timeIntervalSince1970 * 1000)
        XCTAssertEqual(name, "comic-reader-backup-20261016-1530")
    }

    // MARK: 合并

    func testMergeAlignsCategoryByNameAndAssignsNewIds() {
        // 备份来源库
        let src = makeDB()
        src.load()
        let backupCat = src.createCategory(name: "连载中", color: "#ef4444")
        write("cover-bytes", coversDir + "/old.jpg")
        src.upsertComic(sampleComic(id: "old-id", source: "/lib/new.cbz", cover: "old.jpg", categories: [backupCat.id]))
        src.upsertComic(sampleComic(id: "dup-id", source: "/lib/existing.cbz"))
        let exported = BackupCodec.export(db: src, parentDir: root, coversDir: coversDir, now: 0)
        guard let backupDir = exported.path else { return XCTFail("缺少备份目录") }

        // 目标库：已有同名分类（不同 id）与其中一本
        let dstSupport = root + "/dst-support"
        let dstCovers = dstSupport + "/covers"
        try? FileManager.default.createDirectory(atPath: dstCovers, withIntermediateDirectories: true)
        let dst = LibraryDatabase(
            paths: AppPaths(supportDir: dstSupport, comicsDir: comicsDir),
            clock: manual.clock, now: { [weak manual] in manual?.currentTime ?? 0 }
        )
        dst.load()
        let localCat = dst.createCategory(name: "连载中")
        dst.upsertComic(sampleComic(id: "local-dup", source: "/lib/existing.cbz"))

        let result = BackupCodec.restore(
            fromBackupDir: backupDir, mode: .merge,
            db: dst, coversDir: dstCovers, now: 0
        )
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.skipped, 1, "来源相同的漫画应被跳过")
        XCTAssertEqual(dst.listCategories().count, 1, "同名分类应复用而不是新建")

        let imported = dst.listComics().first { $0.sourcePath == "/lib/new.cbz" }
        XCTAssertNotNil(imported)
        XCTAssertNotEqual(imported?.id, "old-id", "合并导入必须分配新 id")
        XCTAssertEqual(imported?.categoryIds, [localCat.id], "分类 id 应映射到本地同名分类")
        XCTAssertEqual(imported?.title, "标题-old-id")
        XCTAssertEqual(imported?.lastReadPage, 2, "进度应随备份带过来")
        XCTAssertEqual(imported?.style, .manga)

        // 封面复制为 <newId>.jpg
        let newId = imported?.id ?? ""
        XCTAssertEqual(imported?.coverFile, "\(newId).jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dstCovers + "/\(newId).jpg"))
    }

    // MARK: 覆盖

    func testReplaceRestoresAndCleansCovers() {
        // 备份来源：一本带封面的漫画
        let src = makeDB()
        src.load()
        write("keep-bytes", coversDir + "/keep.jpg")
        src.upsertComic(sampleComic(id: "k1", source: "/lib/keep.cbz", cover: "keep.jpg"))
        let exported = BackupCodec.export(db: src, parentDir: root, coversDir: coversDir, now: 0)
        guard let backupDir = exported.path else { return XCTFail("缺少备份目录") }

        // 目标库：已有另一本 + 一张过期封面 + 现有 library.json
        let dstSupport = root + "/dst-support"
        let dstCovers = dstSupport + "/covers"
        try? FileManager.default.createDirectory(atPath: dstCovers, withIntermediateDirectories: true)
        let dst = LibraryDatabase(
            paths: AppPaths(supportDir: dstSupport, comicsDir: comicsDir),
            clock: manual.clock, now: { [weak manual] in manual?.currentTime ?? 0 }
        )
        dst.load()
        dst.upsertComic(sampleComic(id: "stale", source: "/lib/stale.cbz", cover: "stale.jpg"))
        write("stale-bytes", dstCovers + "/stale.jpg")
        dst.flushSync()

        let result = BackupCodec.restore(
            fromBackupDir: backupDir, mode: .replace,
            db: dst, coversDir: dstCovers, now: 0
        )
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(dst.listComics().map(\.id), ["k1"], "整库替换")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dstCovers + "/keep.jpg"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dstCovers + "/stale.jpg"), "无主封面应被清理")

        let baks = (try? FileManager.default.contentsOfDirectory(atPath: dstSupport))?
            .filter { $0.contains(".pre-restore-") } ?? []
        XCTAssertEqual(baks.count, 1, "替换前应自动备份当前 library.json")
    }

    func testRestoreRejectsDirectoryWithoutLibraryJSON() {
        let emptyDir = root + "/not-a-backup"
        try? FileManager.default.createDirectory(atPath: emptyDir, withIntermediateDirectories: true)
        let db = makeDB()
        db.load()
        let result = BackupCodec.restore(
            fromBackupDir: emptyDir, mode: .merge, db: db, coversDir: coversDir, now: 0
        )
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "这个文件夹里没有可用的 library.json，请选择备份目录本身")
    }

    // MARK: zip 往返（iOS 交付层）

    #if canImport(ZIPFoundation)
    func testZipRoundTrip() throws {
        let src = root + "/zip-src"
        try FileManager.default.createDirectory(atPath: src + "/covers", withIntermediateDirectories: true)
        write(#"{"version":5}"#, src + "/library.json")
        write("cover-bytes", src + "/covers/a.jpg")

        let data = try BackupCodec.zipDirectory(src)
        XCTAssertGreaterThan(data.count, 0)

        let dst = root + "/zip-dst"
        try BackupCodec.unzip(data, to: dst)
        XCTAssertEqual(
            try String(contentsOfFile: dst + "/library.json", encoding: .utf8),
            #"{"version":5}"#
        )
        XCTAssertEqual(
            try String(contentsOfFile: dst + "/covers/a.jpg", encoding: .utf8),
            "cover-bytes"
        )
    }

    func testUnzipRejectsNonEmptyDirectory() throws {
        let src = root + "/zip-src2"
        try FileManager.default.createDirectory(atPath: src, withIntermediateDirectories: true)
        write("x", src + "/file.txt")
        let data = try BackupCodec.zipDirectory(src)

        let dst = root + "/zip-dst2"
        try FileManager.default.createDirectory(atPath: dst, withIntermediateDirectories: true)
        write("occupied", dst + "/existing.txt")
        XCTAssertThrowsError(try BackupCodec.unzip(data, to: dst), "目标非空必须拒绝，避免覆盖用户数据")
    }
    #endif
}
