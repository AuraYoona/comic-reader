import XCTest
@testable import ComicReaderCore

// HandleCache 的 LRU / 空闲释放 / 并发合并语义（对照 handleCache.ts 的行为）

final class HandleCacheTests: XCTestCase {
    /// 记录 open/close 调用的测试替身
    final class Recorder: @unchecked Sendable {
        let lock = NSLock()
        private(set) var opened: [String] = []
        private(set) var closed: [String] = []

        func onOpen(_ key: String) -> String { lock.lock(); opened.append(key); lock.unlock(); return "handle(\(key))" }
        func onClose(_ value: String) { lock.lock(); closed.append(String(value.dropFirst(8).dropLast(1))); lock.unlock() }
    }

    private func makeCache(recorder: Recorder, max: Int = 2, idle: Double = 3600) -> HandleCache<String> {
        HandleCache(options: HandleCacheOptions<String>(
            max: max,
            idleSeconds: idle,
            open: { recorder.onOpen($0) },
            close: { recorder.onClose($0) }
        ))
    }

    func testReusesOpenHandle() async throws {
        let recorder = Recorder()
        let cache = makeCache(recorder: recorder)
        _ = try await cache.acquire("a.cbz")
        _ = try await cache.acquire("a.cbz")
        XCTAssertEqual(recorder.opened.count, 1, "同一文件不应重复打开")
    }

    func testEvictsOldestWhenOverCapacity() async throws {
        let recorder = Recorder()
        let cache = makeCache(recorder: recorder, max: 2)
        _ = try await cache.acquire("a.cbz")
        _ = try await cache.acquire("b.cbz")
        _ = try await cache.acquire("a.cbz") // a 变最新
        _ = try await cache.acquire("c.cbz")  // 淘汰 b
        XCTAssertTrue(recorder.closed.contains("b.cbz"), "最旧的 b 应被淘汰")
        XCTAssertFalse(recorder.closed.contains("a.cbz"))
    }

    func testConcurrentAcquiresCoalesceIntoOneOpen() async throws {
        let recorder = Recorder()
        let cache = makeCache(recorder: recorder)
        // 并发 20 次同一个 key：只应打开一次
        try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<20 {
                group.addTask { try await cache.acquire("same.cbz") }
            }
            var results: Set<String> = []
            for try await value in group { results.insert(value) }
            XCTAssertEqual(results, ["handle(same.cbz)"])
        }
        XCTAssertEqual(recorder.opened.count, 1, "并发打开必须合并成一次")
    }

    func testReleaseClosesHandle() async throws {
        let recorder = Recorder()
        let cache = makeCache(recorder: recorder)
        _ = try await cache.acquire("a.cbz")
        cache.release("a.cbz")
        XCTAssertTrue(recorder.closed.contains("a.cbz"))
        // 再取会重新打开
        _ = try await cache.acquire("a.cbz")
        XCTAssertEqual(recorder.opened.count, 2)
    }

    func testReleaseAllClosesEverything() async throws {
        let recorder = Recorder()
        let cache = makeCache(recorder: recorder)
        _ = try await cache.acquire("a.cbz")
        _ = try await cache.acquire("b.cbz")
        cache.releaseAll()
        XCTAssertEqual(Set(recorder.closed), ["a.cbz", "b.cbz"])
    }
}

// SourceScanner 门面的行为测试（folder 扫描 + 过滤 + 自然排序 + 重试语义）
final class SourceScannerTests: XCTestCase {
    private var tmpDir: String!

    override func setUp() {
        super.setUp()
        tmpDir = NSTemporaryDirectory() + "/scanner-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if tmpDir != nil { try? FileManager.default.removeItem(atPath: tmpDir) }
        super.tearDown()
    }

    private func write(_ data: String, _ rel: String) {
        let path = tmpDir + "/" + rel
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: path, contents: Data(data.utf8))
    }

    func testScanFolderFiltersJunkAndSortsNaturally() throws {
        write("p1", "10.jpg")
        write("p2", "1.jpg")
        write("p3", "2.jpg")
        write("junk", ".DS_Store")
        write("junk", "__MACOSX/hidden/3.jpg")
        write("sub", "vol1/sub/4.png")

        let pages = try scanSource(sourceType: .folder, sourcePath: tmpDir)
        XCTAssertEqual(pages, ["1.jpg", "2.jpg", "10.jpg", "vol1/sub/4.png"])
    }

    func testScanMissingFolderThrows() {
        XCTAssertThrowsError(try scanSource(sourceType: .folder, sourcePath: tmpDir + "/nope")) { error in
            XCTAssertTrue(error is SourceError)
        }
    }

    func testReadFolderEntry() throws {
        write("hello", "a.jpg")
        let bytes = try readEntry(sourceType: .folder, sourcePath: tmpDir, entry: "a.jpg")
        XCTAssertEqual(bytes.data, Data("hello".utf8))
        XCTAssertEqual(bytes.mime, "image/jpeg")
    }

    func testReadPageBoundsCheck() throws {
        write("x", "only.jpg")
        let comic = Comic(id: "c1", title: "T", sourceType: .folder, sourcePath: tmpDir, pageCount: 1, addedAt: 0)
        invalidateComic("c1")
        let page = try readPage(comic, index: 0)
        XCTAssertEqual(page.data, Data("x".utf8))
        XCTAssertThrowsError(try readPage(comic, index: 5)) { error in
            XCTAssertTrue(error is SourceError)
        }
    }
}
