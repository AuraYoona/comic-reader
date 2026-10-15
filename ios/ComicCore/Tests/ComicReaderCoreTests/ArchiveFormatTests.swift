import XCTest
@testable import ComicReaderCore

// tests/unit/archives.test.ts 的移植

final class ArchiveFormatTests: XCTestCase {
    // MARK: isArchivePath

    func testRecognizesArchivesAndPDFCaseInsensitive() {
        XCTAssertTrue(isArchivePath("a.zip"))
        XCTAssertTrue(isArchivePath("a.CBZ"))
        XCTAssertTrue(isArchivePath("a.rar"))
        XCTAssertTrue(isArchivePath("a.CbR"))
        XCTAssertTrue(isArchivePath("a.pdf"))
        XCTAssertTrue(isArchivePath("a.PDF"))
    }

    func testRejectsOtherTypesAndNoExtension() {
        XCTAssertFalse(isArchivePath("a.7z"))
        XCTAssertFalse(isArchivePath("a.epub"))
        XCTAssertFalse(isArchivePath("folder"))
        XCTAssertFalse(isArchivePath(".zip")) // 隐藏文件，不算扩展名
    }

    func testOnlyLooksAtLastSegment() {
        XCTAssertFalse(isArchivePath("D:/a.zip/b"))
        XCTAssertTrue(isArchivePath("D:/dir.rar/vol1.cbz"))
        XCTAssertTrue(isArchivePath("D:/dir/vol1.pdf"))
    }

    func testAllFiveExtensionsPresent() {
        XCTAssertEqual(ARCHIVE_EXTS.sorted(), ["cbz", "cbr", "pdf", "rar", "zip"])
    }

    // MARK: stripArchiveExt

    func testStripsArchiveExt() {
        XCTAssertEqual(stripArchiveExt("孤独摇滚 v01.cbz"), "孤独摇滚 v01")
        XCTAssertEqual(stripArchiveExt("x.RAR"), "x")
        XCTAssertEqual(stripArchiveExt("第01卷.PDF"), "第01卷")
    }

    func testNonArchiveReturnedAsIs() {
        XCTAssertEqual(stripArchiveExt("普通文件夹"), "普通文件夹")
        XCTAssertEqual(stripArchiveExt("封面.jpg"), "封面.jpg")
    }

    func testOnlyStripsLastExt() {
        XCTAssertEqual(stripArchiveExt("vol.1.cbz"), "vol.1")
    }

    // MARK: covers

    func testGeneratedCoverJpg() {
        XCTAssertTrue(isGeneratedCover("abc-123.jpg"))
        XCTAssertTrue(isGeneratedCover("abc-123.JPG"))
        XCTAssertFalse(coverNeedsThumbnail("abc-123.jpg"))
    }

    func testOriginalCoverNeedsThumbnail() {
        XCTAssertFalse(isGeneratedCover("abc.webp"))
        XCTAssertTrue(coverNeedsThumbnail("abc.webp"))
        XCTAssertTrue(coverNeedsThumbnail("abc.avif"))
        XCTAssertTrue(coverNeedsThumbnail("abc.gif"))
    }

    func testNoCoverNeedsNothing() {
        XCTAssertFalse(isGeneratedCover(nil))
        XCTAssertFalse(coverNeedsThumbnail(nil))
    }

    // MARK: isImagePath / isJunkEntry（tests/unit/images.test.ts 的关键用例）

    func testImagePathAcceptsKnownExtensions() {
        for ext in ["jpg", "jpeg", "jfif", "png", "webp", "gif", "avif", "bmp"] {
            XCTAssertTrue(isImagePath("cover.\(ext)"), "cover.\(ext) 应被识别为页面")
        }
        XCTAssertTrue(isImagePath("a.JPEG"))
    }
    func testImagePathRejectsUnknownAndHidden() {
        XCTAssertFalse(isImagePath("cover.txt"))
        XCTAssertFalse(isImagePath("cover.svg"))
        XCTAssertFalse(isImagePath("cover.pdf"))
        XCTAssertFalse(isImagePath("cover.jpg.exe"))
        XCTAssertFalse(isImagePath("noext"))
        XCTAssertFalse(isImagePath(".DS_Store"))
        XCTAssertFalse(isImagePath("._page1.jpg"))
        XCTAssertTrue(isImagePath("_001.jpg")) // 下划线开头的保留
        XCTAssertTrue(isImagePath("a.BMP"))
    }

    func testJunkEntries() {
        XCTAssertTrue(isJunkEntry("__MACOSX/vol1/1.jpg"))
        XCTAssertTrue(isJunkEntry("__MACOSXextra/x.jpg"))
        XCTAssertTrue(isJunkEntry("ok/.DS_Store"))
        XCTAssertTrue(isJunkEntry(".hidden/page.jpg"))
        XCTAssertFalse(isJunkEntry("vol1/1.jpg"))
    }

    // MARK: mimeFor

    func testMimeFor() {
        XCTAssertEqual(mimeFor("a.jpg"), "image/jpeg")
        XCTAssertEqual(mimeFor("a.jpeg"), "image/jpeg")
        XCTAssertEqual(mimeFor("a.jfif"), "image/jpeg")
        XCTAssertEqual(mimeFor("a.PNG"), "image/png")
        XCTAssertEqual(mimeFor("a.webp"), "image/webp")
        XCTAssertEqual(mimeFor("a.gif"), "image/gif")
        XCTAssertEqual(mimeFor("a.avif"), "image/avif")
        XCTAssertEqual(mimeFor("a.bmp"), "image/bmp")
        XCTAssertEqual(mimeFor("a.txt"), "application/octet-stream")
    }

    // MARK: 数值 clamp（types.ts 的关键用例）

    func testClampZoomScale() {
        XCTAssertEqual(ZoomLimits.clampScale(0.1), 0.25)
        XCTAssertEqual(ZoomLimits.clampScale(5), 4)
        XCTAssertEqual(ZoomLimits.clampScale(1.234), 1.23)
        XCTAssertEqual(ZoomLimits.clampScale(1.555), 1.56)
        XCTAssertEqual(ZoomLimits.clampScale(.infinity), 1)
    }

    func testClampBrightness() {
        XCTAssertEqual(BrightnessLimits.clamp(0.1), 0.3)
        XCTAssertEqual(BrightnessLimits.clamp(1.5), 1.2)
        XCTAssertEqual(BrightnessLimits.clamp(0.626), 0.63) // 0.05 步进
        XCTAssertEqual(BrightnessLimits.clamp(1), 1)
    }

    func testClampAutoTurn() {
        XCTAssertEqual(AutoTurnLimits.clamp(0), 2)
        XCTAssertEqual(AutoTurnLimits.clamp(100), 60)
        XCTAssertEqual(AutoTurnLimits.clamp(6), 6)
    }

    func testClampAutoScroll() {
        XCTAssertEqual(AutoScrollLimits.clamp(5), 10)
        XCTAssertEqual(AutoScrollLimits.clamp(500), 400)
        XCTAssertEqual(AutoScrollLimits.clamp(83), 80) // 10 步进取整
        XCTAssertEqual(AutoScrollLimits.clamp(87), 90)
    }

    func testStylePresets() {
        let manga = comicStylePreset(.manga)
        XCTAssertEqual(manga.mode, .single)
        XCTAssertEqual(manga.direction, .rtl)
        XCTAssertEqual(manga.pageOffset, 1)
        XCTAssertEqual(manga.autoScroll, false)

        let manhwa = comicStylePreset(.manhwa)
        XCTAssertEqual(manhwa.mode, .scroll)
        XCTAssertEqual(manhwa.direction, .ltr)
        XCTAssertEqual(manhwa.autoScroll, true)

        XCTAssertEqual(comicStylePreset(.manhua), manhwa)

        let western = comicStylePreset(.western)
        XCTAssertEqual(western.mode, .single)
        XCTAssertEqual(western.direction, .ltr)
        XCTAssertEqual(western.autoScroll, false)
    }
}
