import XCTest
@testable import ComicReaderCore

// TransferNaming：文件名净化、扩展名白名单、重名编号、下载头编码

final class TransferNamingTests: XCTestCase {
    func testValidNames() {
        XCTAssertEqual(TransferNaming.sanitizeFileName("漫画 01.cbz"), "漫画 01.cbz")
        XCTAssertEqual(TransferNaming.sanitizeFileName("One Piece #1 (2024).pdf"), "One Piece #1 (2024).pdf")
        XCTAssertEqual(TransferNaming.sanitizeFileName("  a+b.cbr  "), "a+b.cbr")
        // NFC 归一化（e + 组合重音 → é）
        XCTAssertEqual(TransferNaming.sanitizeFileName("e\u{301}.cbz"), "\u{E9}.cbz")
    }

    func testRejectedNames() {
        let bad = [
            "",
            "   ",
            ".hidden.cbz",
            ".",
            "..",
            "a/b.cbz",
            "a\\b.cbz",
            "a:b.cbz",
            "a<b.cbz",
            "a>b.cbz",
            "a\"b.cbz",
            "a|b.cbz",
            "a?b.cbz",
            "a*b.cbz",
            "a\u{0}b.cbz",
            "a\nb.cbz",
            "a.",
            String(repeating: "a", count: 197) + ".cbz",
        ]
        for name in bad {
            XCTAssertNil(TransferNaming.sanitizeFileName(name), "should reject: \(name.debugDescription)")
        }
    }

    func testLengthBoundary() {
        let exactly200 = String(repeating: "a", count: 196) + ".cbz"
        XCTAssertEqual(exactly200.count, 200)
        XCTAssertNotNil(TransferNaming.sanitizeFileName(exactly200))

        // 字符数没超，但 UTF-8 字节数超过 200（Darwin 路径分量上限 255 字节）
        let longChinese = String(repeating: "漫", count: 90) + ".cbz"
        XCTAssertLessThanOrEqual(longChinese.count, TransferNaming.maxFileNameLength)
        XCTAssertGreaterThan(longChinese.utf8.count, TransferNaming.maxFileNameBytes)
        XCTAssertNil(TransferNaming.sanitizeFileName(longChinese))

        let okChinese = String(repeating: "漫", count: 60) + ".cbz"
        XCTAssertNotNil(TransferNaming.sanitizeFileName(okChinese))
    }

    func testAllowedExtensions() {
        for name in ["a.cbz", "A.CBZ", "a.zip", "a.rar", "a.cbr", "a.pdf"] {
            XCTAssertTrue(TransferNaming.isAllowedComicFile(name), name)
        }
        for name in ["a.exe", "a", "a.cbz.txt", "a.7z", ".cbz"] {
            XCTAssertFalse(TransferNaming.isAllowedComicFile(name), name)
        }
    }

    func testUniqueFileName() {
        var existing: Set<String> = ["a.cbz"]
        XCTAssertEqual(
            TransferNaming.uniqueFileName(preferred: "a.cbz") { existing.contains($0) },
            "a (2).cbz"
        )
        existing.insert("a (2).cbz")
        XCTAssertEqual(
            TransferNaming.uniqueFileName(preferred: "a.cbz") { existing.contains($0) },
            "a (3).cbz"
        )
        XCTAssertEqual(
            TransferNaming.uniqueFileName(preferred: "free.cbz") { existing.contains($0) },
            "free.cbz"
        )
        XCTAssertEqual(
            TransferNaming.uniqueFileName(preferred: "noext") { $0 == "noext" },
            "noext (2)"
        )
        XCTAssertEqual(
            TransferNaming.uniqueFileName(preferred: "漫画.cbz") { $0 == "漫画.cbz" },
            "漫画 (2).cbz"
        )
    }

    func testContentDispositionEncodesUTF8() {
        let header = TransferNaming.contentDisposition(fileName: "漫画 01.cbz")
        XCTAssertTrue(header.hasPrefix("attachment; "))
        XCTAssertTrue(header.contains("filename*=UTF-8''%E6%BC%AB%E7%94%BB%2001.cbz"))
        XCTAssertTrue(header.contains("filename=\""))
        XCTAssertFalse(header.contains("\r"))
        XCTAssertFalse(header.contains("\n"))
    }

    func testContentDispositionStripsHeaderInjection() {
        let header = TransferNaming.contentDisposition(fileName: "a\"b\r\nX-Evil: 1.cbz")
        XCTAssertFalse(header.contains("\r"))
        XCTAssertFalse(header.contains("\n"))
        XCTAssertFalse(header.contains("a\"b"))
    }

    func testAsciiFallbackForNonLatinTitle() {
        let header = TransferNaming.contentDisposition(fileName: "漫画.cbz")
        XCTAssertTrue(header.contains("filename=\"download.cbz\""), header)
    }
}
