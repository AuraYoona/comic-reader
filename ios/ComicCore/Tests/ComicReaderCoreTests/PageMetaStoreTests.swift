import XCTest
@testable import ComicReaderCore

// PageMetaStore：round-trip / 防抖合并 / 损坏容错 / 截断 / 换本切换

final class PageMetaStoreTests: XCTestCase {
    private var dir: String!

    override func setUp() {
        super.setUp()
        dir = NSTemporaryDirectory() + "/pagemeta-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if dir != nil { try? FileManager.default.removeItem(atPath: dir) }
        super.tearDown()
    }

    func testRoundTripWithDebouncedWrite() {
        let manual = ManualClock()
        let store = PageMetaStore(dir: dir, clock: manual.clock)

        let loaded = store.load(comicId: "c1")
        XCTAssertEqual(loaded.ratios.count, 0, "新漫画应从空表开始")

        store.setRatio(index: 3, ratio: 8.2)
        store.setRatio(index: 3, ratio: 8.205) // 阈值内：不重复标脏
        store.setRatio(index: 7, ratio: 1.4)
        store.setScroll(page: 7, fraction: 0.42)
        manual.advance(by: 5) // 5s 进度防抖到期 → 落盘

        // 重开 round-trip（live 时钟只读不排程）
        let reloaded = PageMetaStore(dir: dir).load(comicId: "c1")
        XCTAssertEqual(reloaded.ratios[3] ?? 0, 8.2, accuracy: 0.001)
        XCTAssertEqual(reloaded.ratios[7] ?? 0, 1.4, accuracy: 0.001)
        XCTAssertEqual(reloaded.scrollPage, 7)
        XCTAssertEqual(reloaded.scrollFraction ?? 0, 0.42, accuracy: 0.001)
    }

    func testSetScrollSameValuesNotDirty() {
        let manual = ManualClock()
        let store = PageMetaStore(dir: dir, clock: manual.clock)
        _ = store.load(comicId: "c1")
        store.setScroll(page: 2, fraction: 0.5)
        store.flushSync()

        // 从磁盘态重载后写回相同值（阈值内）：不应标脏 → 不应重建被删的文件
        _ = store.load(comicId: "c1")
        try? FileManager.default.removeItem(atPath: dir + "/c1.json")
        store.setScroll(page: 2, fraction: 0.501)
        manual.advance(by: 5)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: dir + "/c1.json"),
            "未变化的写不应触发落盘"
        )
    }

    func testFlushSyncWritesImmediately() {
        let manual = ManualClock()
        let store = PageMetaStore(dir: dir, clock: manual.clock)
        _ = store.load(comicId: "c2")
        store.setRatio(index: 1, ratio: 2.5)
        store.flushSync()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir + "/c2.json"))
        let meta = store.current()
        XCTAssertEqual(meta.ratios[1] ?? 0, 2.5, accuracy: 0.001)
    }

    func testCorruptFileFallsBackToEmptyWithBackup() {
        try? Data("not json".utf8).write(to: URL(fileURLWithPath: dir + "/c3.json"))
        let store = PageMetaStore(dir: dir)
        let meta = store.load(comicId: "c3")
        XCTAssertEqual(meta.ratios.count, 0, "损坏文件应按空表启动")

        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        XCTAssertTrue(names.contains { $0.hasPrefix("c3.json.corrupt-") }, "损坏文件应改名留证")
    }

    func testTruncateDropsOutOfRangeRatios() {
        let manual = ManualClock()
        let store = PageMetaStore(dir: dir, clock: manual.clock)
        _ = store.load(comicId: "c4")
        store.setRatio(index: 2, ratio: 1.5)
        store.setRatio(index: 9, ratio: 3.0)
        store.truncate(pageCount: 5)
        let meta = store.current()
        XCTAssertNil(meta.ratios[9], "越界键应被截断")
        XCTAssertNotNil(meta.ratios[2])
    }

    func testSwitchComicLoadsItsOwnFile() {
        let manual = ManualClock()
        let store = PageMetaStore(dir: dir, clock: manual.clock)
        _ = store.load(comicId: "a")
        store.setRatio(index: 0, ratio: 1.2)
        store.flushSync()

        _ = store.load(comicId: "b")
        XCTAssertEqual(store.current().ratios.count, 0, "换本后内存只持新本")

        _ = store.load(comicId: "a")
        XCTAssertEqual(store.current().ratios[0] ?? 0, 1.2, accuracy: 0.001)
    }
}
