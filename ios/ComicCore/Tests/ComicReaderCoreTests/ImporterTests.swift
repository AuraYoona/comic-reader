import XCTest
@testable import ComicReaderCore

// Importer 的导入语义（对照 src/main/importer.ts）

/// 固定输出的封面工厂：记录每次收到的第一页字节
final class FakeCoverMaker: CoverMaking, @unchecked Sendable {
    private let lock = NSLock()
    private let output: Data?
    private var inputs: [Data] = []

    init(output: Data?) {
        self.output = output
    }

    func makeCover(fromPageData data: Data) -> Data? {
        lock.lock(); defer { lock.unlock() }
        inputs.append(data)
        return output
    }

    var inputCount: Int {
        lock.lock(); defer { lock.unlock() }
        return inputs.count
    }

    var firstInput: Data? {
        lock.lock(); defer { lock.unlock() }
        return inputs.first
    }
}

/// 线程安全的进度记录（@Sendable 闭包不能捕获可变局部变量）
final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [ImportProgressInfo] = []

    func append(_ info: ImportProgressInfo) {
        lock.lock(); defer { lock.unlock() }
        entries.append(info)
    }

    var snapshot: [ImportProgressInfo] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }
}

/// 注入的 addedAt 时钟（毫秒）
private let fixedImportTime: Double = 1_700_000_000_000

final class ImporterTests: XCTestCase {
    private var root: String!
    private var paths: AppPaths!
    private var manual: ManualClock!

    override func setUp() {
        super.setUp()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("importer-test-\(UUID().uuidString)")
            .path
        try? FileManager.default.createDirectory(atPath: root + "/support", withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: root + "/comics", withIntermediateDirectories: true)
        paths = AppPaths(supportDir: root + "/support", comicsDir: root + "/comics")
        manual = ManualClock()
    }

    override func tearDown() {
        if let root { try? FileManager.default.removeItem(atPath: root) }
        super.tearDown()
    }

    // MARK: 工具

    private func makeDB() -> LibraryDatabase {
        let db = LibraryDatabase(paths: paths, clock: manual.clock, now: { [weak manual] in manual?.currentTime ?? 0 })
        db.load()
        return db
    }

    private func makeImporter(db: LibraryDatabase, coverFactory: (any CoverMaking)? = nil) -> Importer {
        Importer(db: db, coversDir: paths.coversDir, coverFactory: coverFactory, now: { fixedImportTime })
    }

    /// 建一个漫画文件夹；pages 为文件名列表（扩展名需落在图片白名单内）
    @discardableResult
    private func makeFolder(_ name: String, in parent: String, pages: [String]) -> String {
        let dir = parent + "/" + name
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (index, page) in pages.enumerated() {
            _ = FileManager.default.createFile(atPath: dir + "/" + page, contents: Data("page-\(index)".utf8))
        }
        return dir
    }

    // MARK: 单项导入

    func testImportFolderComicSucceeds() {
        let db = makeDB()
        let maker = FakeCoverMaker(output: Data([0xff, 0xd8, 0xff, 0xe0]))
        let importer = makeImporter(db: db, coverFactory: maker)
        let folder = makeFolder("我的漫画", in: root, pages: ["01.jpg", "02.jpg", "03.png"])

        let results = importer.importPaths([folder])

        XCTAssertEqual(results.count, 1)
        let result = results[0]
        XCTAssertEqual(result.status, .imported)
        XCTAssertEqual(result.path, folder)
        guard let comic = result.comic else {
            return XCTFail("导入成功应带回 comic")
        }
        XCTAssertEqual(comic.title, "我的漫画")
        XCTAssertEqual(comic.sourceType, .folder)
        XCTAssertEqual(comic.sourcePath, folder)
        XCTAssertEqual(comic.pageCount, 3)
        XCTAssertEqual(comic.addedAt, fixedImportTime)
        XCTAssertNil(comic.lastReadAt)
        XCTAssertEqual(comic.lastReadPage, 0)
        XCTAssertEqual(comic.reader, ComicReaderPrefs())
        XCTAssertEqual(comic.categoryIds, [])
        XCTAssertEqual(comic.bookmarks, [])
        XCTAssertNil(comic.style)
        XCTAssertEqual(db.listComics().map(\.id), [comic.id], "应已落库")

        // 封面：第一页（自然排序后）的字节交给工厂，产物写 coversDir/<comic.id>.jpg
        XCTAssertEqual(maker.inputCount, 1)
        XCTAssertEqual(maker.firstInput, Data("page-0".utf8))
        XCTAssertEqual(comic.coverFile, comic.id + ".jpg")
        let coverPath = paths.coversDir + "/" + (comic.coverFile ?? "")
        XCTAssertEqual(FileManager.default.contents(atPath: coverPath), Data([0xff, 0xd8, 0xff, 0xe0]))
    }

    func testDuplicateBatchEntryAndAlreadyOnShelf() {
        let db = makeDB()
        let importer = makeImporter(db: db)
        let folder = makeFolder("重复", in: root, pages: ["1.jpg"])

        // 同批重复：第一次导入，第二次「重复选择」
        let batch = importer.importPaths([folder, folder])
        XCTAssertEqual(batch.map(\.status), [.imported, .skipped])
        XCTAssertEqual(batch[1].reason, "重复选择")
        XCTAssertNil(batch[0].comic?.coverFile, "未注入封面工厂时 coverFile 为 nil")
        XCTAssertEqual(db.listComics().count, 1)

        // 已在书架：带回已有记录；末尾斜杠变体归一化后同样命中
        let again = importer.importPaths([folder + "/"])
        XCTAssertEqual(again[0].status, .skipped)
        XCTAssertEqual(again[0].reason, "已在书架中")
        XCTAssertEqual(again[0].comic?.id, batch[0].comic?.id)
        XCTAssertEqual(again[0].path, folder, "末尾斜杠应被归一化")
        XCTAssertEqual(db.listComics().count, 1)
    }

    func testEmptyFolderFails() {
        let db = makeDB()
        let importer = makeImporter(db: db)
        let folder = makeFolder("空目录", in: root, pages: [])

        let results = importer.importPaths([folder])
        XCTAssertEqual(results[0].status, .failed)
        XCTAssertEqual(results[0].reason, "文件夹中没有找到图片")
        XCTAssertTrue(db.listComics().isEmpty)
    }

    func testMissingPathAndUnsupportedTypeFail() {
        let db = makeDB()
        let importer = makeImporter(db: db)
        let missing = root + "/没有这个"
        let textFile = root + "/notes.txt"
        _ = FileManager.default.createFile(atPath: textFile, contents: Data("x".utf8))

        let results = importer.importPaths([missing, textFile])
        XCTAssertEqual(results[0].status, .failed)
        XCTAssertEqual(results[0].reason, "路径不存在")
        XCTAssertEqual(results[1].status, .failed)
        XCTAssertEqual(results[1].reason, "不支持的文件类型（支持文件夹、ZIP / CBZ / RAR / CBR 与 PDF）")
        XCTAssertTrue(db.listComics().isEmpty)
    }

    func testCoverFailureDoesNotBlockImport() {
        let db = makeDB()
        let maker = FakeCoverMaker(output: nil)
        let importer = makeImporter(db: db, coverFactory: maker)
        let folder = makeFolder("无封面", in: root, pages: ["1.jpg"])

        let results = importer.importPaths([folder])
        XCTAssertEqual(results[0].status, .imported)
        XCTAssertNil(results[0].comic?.coverFile)
        XCTAssertEqual(maker.inputCount, 1, "仍应尝试读第一页")
        let covers = (try? FileManager.default.contentsOfDirectory(atPath: paths.coversDir)) ?? []
        XCTAssertTrue(covers.isEmpty, "生成失败不应留下文件")
    }

    // MARK: 库根目录

    func testExpandBatchRootListsOneLevelAndSkipsHidden() {
        let db = makeDB()
        let importer = makeImporter(db: db)
        let batch = root + "/batch"
        try? FileManager.default.createDirectory(atPath: batch, withIntermediateDirectories: true)
        let series = makeFolder("系列A", in: batch, pages: ["1.jpg"])
        makeFolder("系列A/嵌套", in: batch, pages: [])
        _ = FileManager.default.createFile(atPath: batch + "/book.cbz", contents: Data())
        _ = FileManager.default.createFile(atPath: batch + "/notes.txt", contents: Data())
        makeFolder(".hidden", in: batch, pages: [])
        makeFolder("__MACOSX", in: batch, pages: [])

        let targets = importer.expandBatchRoot(batch)
        XCTAssertEqual(targets?.count, 2, "只列一层：子目录 + 压缩包各一项")
        XCTAssertEqual(Set(targets ?? []), Set([series, batch + "/book.cbz"]))
        XCTAssertNil(importer.expandBatchRoot(root + "/不存在"), "根读不了返回 nil")
    }

    func testFindUnimportedExcludesOnShelf() {
        let db = makeDB()
        let importer = makeImporter(db: db)
        let lib = root + "/lib"
        let done = makeFolder("已导入", in: lib, pages: ["1.jpg"])
        let todo = makeFolder("还没导入", in: lib, pages: ["1.jpg"])

        _ = importer.importPaths([done])

        XCTAssertEqual(importer.findUnimported(inRoot: lib), [todo])
        XCTAssertEqual(importer.findUnimported(inRoot: root + "/不存在"), [], "读不了的根返回空数组")
    }

    func testScanLibraryRootsImportsNewAndReportsUnreadable() {
        let db = makeDB()
        let importer = makeImporter(db: db)
        let lib = root + "/lib"
        let newComic = makeFolder("新漫画", in: lib, pages: ["1.jpg", "2.jpg"])
        let missingRoot = root + "/没有这个根"
        db.saveSettings { $0.libraryRoots = [lib, missingRoot] }

        let first = importer.scanLibraryRoots()
        XCTAssertEqual(first.roots, 2, "roots 为 settings 记录的根总数（对齐桌面版 roots.length）")
        XCTAssertEqual(first.unreadable, [missingRoot])
        XCTAssertEqual(first.added.map(\.title), ["新漫画"])
        XCTAssertEqual(first.added.first?.sourcePath, newComic)
        XCTAssertEqual(db.listComics().map(\.id), first.added.map(\.id))

        // 增量：再扫不重复上架
        let second = importer.scanLibraryRoots()
        XCTAssertTrue(second.added.isEmpty)
        XCTAssertEqual(second.unreadable, [missingRoot])
        XCTAssertEqual(second.roots, 2)
        XCTAssertEqual(db.listComics().count, 1)
    }

    // MARK: 进度

    func testImportProgressSequence() {
        let db = makeDB()
        let importer = makeImporter(db: db)
        let folder = makeFolder("进度", in: root, pages: ["1.jpg"])
        let missing = root + "/进-缺"
        let log = ProgressLog()

        let results = importer.importPaths([folder, folder, missing], progress: { log.append($0) })
        XCTAssertEqual(results.map(\.status), [.imported, .skipped, .failed])

        let entries = log.snapshot
        XCTAssertEqual(entries.count, 3, "每项一次，含跳过与失败项")
        XCTAssertEqual(entries.map(\.current), [1, 2, 3])
        XCTAssertEqual(entries.map(\.total), [3, 3, 3])
        XCTAssertEqual(entries.map(\.path), [folder, folder, missing])

        // 空输入：无结果也无回调
        let emptyLog = ProgressLog()
        XCTAssertTrue(importer.importPaths([], progress: { emptyLog.append($0) }).isEmpty)
        XCTAssertTrue(emptyLog.snapshot.isEmpty)
    }
}
