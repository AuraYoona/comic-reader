import XCTest
@testable import ComicReaderCore

// deriveChapters：从页面条目路径推导章节目录

final class ChapterTests: XCTestCase {
    func testNoFoldersYieldsNoChapters() {
        XCTAssertTrue(deriveChapters(from: ["1.jpg", "2.jpg", "10.jpg"]).isEmpty)
        XCTAssertTrue(deriveChapters(from: []).isEmpty)
    }

    func testSingleFolderYieldsNoChapters() {
        // 只有一个章节文件夹：没有目录可言
        XCTAssertTrue(deriveChapters(from: ["全一卷/1.jpg", "全一卷/2.jpg"]).isEmpty)
    }

    func testChapterFoldersGroupContiguously() {
        let pages = [
            "第1话/001.jpg", "第1话/002.jpg",
            "第2话/001.jpg",
            "第10话/001.jpg", "第10话/002.jpg", "第10话/003.jpg",
        ]
        let chapters = deriveChapters(from: pages)
        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(chapters[0], ComicChapter(title: "第1话", startPage: 0, pageCount: 2))
        XCTAssertEqual(chapters[1], ComicChapter(title: "第2话", startPage: 2, pageCount: 1))
        XCTAssertEqual(chapters[2], ComicChapter(title: "第10话", startPage: 3, pageCount: 3))
    }

    func testLooseRootImagesFormLeadingUnnamedChapter() {
        let pages = [
            "封面.png",
            "第1话/001.jpg", "第1话/002.jpg",
            "第2话/001.jpg",
        ]
        let chapters = deriveChapters(from: pages)
        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(chapters[0], ComicChapter(title: "", startPage: 0, pageCount: 1))
        XCTAssertEqual(chapters[1].title, "第1话")
        XCTAssertEqual(chapters[2].title, "第2话")
    }

    func testNestedSubfoldersStayInSameChapter() {
        // 章节文件夹内部的子目录不拆章：仍按首个路径段分组
        let pages = [
            "第1话/sub/001.jpg", "第1话/002.jpg",
            "第2话/001.jpg",
        ]
        let chapters = deriveChapters(from: pages)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].pageCount, 2)
        XCTAssertEqual(chapters[1].title, "第2话")
    }

    func testNonContiguousSameTitleSplitsIntoRuns() {
        // 自然排序让同名段不连续时，按连续段切分（跳章仍正确）
        let pages = [
            "第1话/001.jpg",
            "第2话/001.jpg",
            "第1话/002.jpg", // 同名段回访
        ]
        let chapters = deriveChapters(from: pages)
        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(chapters[0], ComicChapter(title: "第1话", startPage: 0, pageCount: 1))
        XCTAssertEqual(chapters[2], ComicChapter(title: "第1话", startPage: 2, pageCount: 1))
    }

    /// 端到端：真实目录结构 → scanSource 的自然排序 → 章节落在排序后列表上
    func testScanSourceThenDeriveChapters() throws {
        let tmp = NSTemporaryDirectory() + "/chapters-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        func write(_ rel: String) {
            let path = tmp + "/" + rel
            try? FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: path, contents: Data("x".utf8))
        }
        write("第01话/1.jpg")
        write("第01话/2.jpg")
        write("第02话/1.jpg")

        let pages = try scanSource(sourceType: .folder, sourcePath: tmp)
        let chapters = deriveChapters(from: pages)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].startPage, 0)
        XCTAssertEqual(chapters[0].pageCount, 2)
        XCTAssertEqual(chapters[1].title, "第02话")
        XCTAssertEqual(chapters[1].startPage, 2)
        // 章节首页映射回页面条目
        XCTAssertEqual(pages[chapters[1].startPage], "第02话/1.jpg")
    }
}

// stripDedupSuffix / remapPage：同名并入的辅助

final class ImportMergeHelpersTests: XCTestCase {
    func testStripDedupSuffix() {
        XCTAssertEqual(stripDedupSuffix("漫画a"), "漫画a")
        XCTAssertEqual(stripDedupSuffix("漫画a (2)"), "漫画a")
        XCTAssertEqual(stripDedupSuffix("漫画a (12)"), "漫画a")
        XCTAssertEqual(stripDedupSuffix("漫画a (2) (3)"), "漫画a")
        // 目录名本身带 (3) 的（无空格前缀或非纯数字）不动
        XCTAssertEqual(stripDedupSuffix("第3话(1)"), "第3话(1)")
        XCTAssertEqual(stripDedupSuffix("卷 (上)"), "卷 (上)")
    }

    func testRemapPageFindsEntryAfterShift() {
        // 新章节「第00话」插到前面：原第 2 页（第01话/1.jpg）平移到第 4 页
        let old = ["第01话/1.jpg", "第01话/2.jpg", "第02话/1.jpg"]
        let new = ["第00话/1.jpg", "第00话/2.jpg", "第01话/1.jpg", "第01话/2.jpg", "第02话/1.jpg"]
        XCTAssertEqual(remapPage(0, old: old, new: new), 2)
        XCTAssertEqual(remapPage(2, old: old, new: new), 4)
    }

    func testRemapPageAppendedKeepsIndex() {
        let old = ["1.jpg", "2.jpg"]
        let new = ["1.jpg", "2.jpg", "第02话/1.jpg"]
        XCTAssertEqual(remapPage(1, old: old, new: new), 1)
    }

    func testRemapPageMissingEntryFallsBackToRatio() {
        // 原条目消失：按比例近似
        let old = (0..<10).map { "old\($0).jpg" }
        let new = (0..<20).map { "new\($0).jpg" }
        XCTAssertEqual(remapPage(5, old: old, new: new), 10)  // 5/10 → 10/20
    }

    func testRemapPageOutOfRangeClamps() {
        XCTAssertEqual(remapPage(99, old: ["a"], new: ["a", "b"]), 1)
        XCTAssertEqual(remapPage(0, old: ["a"], new: []), 0)
    }
}
