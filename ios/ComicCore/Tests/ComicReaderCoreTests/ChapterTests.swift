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
