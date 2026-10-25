import XCTest
@testable import ComicReaderCore

#if canImport(ZIPFoundation)
// ZipArchiveReader.repairEntryName：GBK 编码文件名的 zip（未设 UTF-8 标志，
// ZIPFoundation 按 CP437 解码成乱码）的修复

final class ZipEntryNameTests: XCTestCase {
    /// 与 ZipArchiveReader 内部相同的 CP437 构造
    private let cp437 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x400))
    )

    func testASCIINameUntouched() {
        XCTAssertEqual(ZipArchiveReader.repairEntryName("ch01/001.jpg"), "ch01/001.jpg")
        XCTAssertEqual(ZipArchiveReader.repairEntryName("001.png"), "001.png")
    }

    func testProperUTF8NameUntouched() {
        // 带 UTF-8 标志的正常中文名：含 CP437 字符集之外的字符，
        // 还原原始字节必然失败 → 原样返回（方向判别）
        XCTAssertEqual(ZipArchiveReader.repairEntryName("第01话/001.jpg"), "第01话/001.jpg")
    }

    func testGBKNameRepaired() {
        // "第01话" 的 GBK 字节：第 = B5 DA，话 = BB B0
        let gbkBytes: [UInt8] = [0xB5, 0xDA, 0x30, 0x31, 0xBB, 0xB0]
        let mojibake = String(data: Data(gbkBytes), encoding: cp437)!
        let repaired = ZipArchiveReader.repairEntryName(mojibake + "/001.jpg")
        XCTAssertEqual(repaired, "第01话/001.jpg")
    }

    func testLatinAccentedNameUntouched() {
        // 合法的重音字符名（CP437 可表示）：还原出的字节既非合法 UTF-8
        // 也非合法 GB18030 → 原样返回
        XCTAssertEqual(ZipArchiveReader.repairEntryName("café/001.jpg"), "café/001.jpg")
    }
}
#endif
