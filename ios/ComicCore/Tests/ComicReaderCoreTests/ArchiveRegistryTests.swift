import XCTest
@testable import ComicReaderCore

// 注册表装配与「扩展名 → 适配器」完整链路。
// 真机首版踩过坑：App 忘了调 installBuiltinReaders，所有压缩包导入
// 都报「不支持的文件格式」——这里按公开入口（scanSource / readerFor）
// 走全链路，防回归。

final class ArchiveRegistryTests: XCTestCase {
    private var root: String!

    override func setUp() {
        super.setUp()
        root = NSTemporaryDirectory() + "/archive-registry-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        sharedArchiveRegistry.installBuiltinReaders()
    }

    override func tearDown() {
        if let root { try? FileManager.default.removeItem(atPath: root) }
        super.tearDown()
    }

    func testScanZipThroughSharedRegistry() throws {
        #if canImport(ZIPFoundation)
        let folder = root + "/pages"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        // scanSource 只按扩展名过滤条目，内容不必是真实图片
        FileManager.default.createFile(atPath: folder + "/001.jpg", contents: Data([1, 2, 3]))
        FileManager.default.createFile(atPath: folder + "002.txt", contents: Data([4]))

        let zipPath = root + "/book.zip"
        try BackupCodec.createZip(ofDirectory: folder, at: zipPath)

        let entries = try scanSource(sourceType: .archive, sourcePath: zipPath)
        XCTAssertEqual(entries, ["001.jpg"])
        #endif
    }

    func testReaderForKnownExtensions() throws {
        #if canImport(ZIPFoundation)
        XCTAssertNoThrow(try sharedArchiveRegistry.reader(for: "/x/a.zip"))
        XCTAssertNoThrow(try sharedArchiveRegistry.reader(for: "/x/A.CBZ"))
        #endif
    }

    func testReaderForUnknownExtensionThrows() {
        XCTAssertThrowsError(try sharedArchiveRegistry.reader(for: "/x/a.exe")) { error in
            guard let sourceError = error as? SourceError else {
                return XCTFail("expected SourceError, got \(error)")
            }
            XCTAssertTrue(sourceError.message.contains("不支持的文件格式"), sourceError.message)
        }
    }
}
