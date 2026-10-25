import XCTest
@testable import ComicReaderCore

// TransferWebPage：占位符替换、设备名转义、接口相对路径

final class TransferWebPageTests: XCTestCase {
    func testAppPageInjectsDeviceAndCount() {
        let page = TransferWebPage.app(deviceName: "Aura 的 iPhone", libraryCount: 42)
        XCTAssertTrue(page.contains("Aura 的 iPhone"))
        XCTAssertTrue(page.contains("书架 42 本"))
        XCTAssertFalse(page.contains("{{"))
    }

    func testAppPageEscapesDeviceName() {
        let page = TransferWebPage.app(
            deviceName: "<script>alert(\"x\")</script>",
            libraryCount: 0
        )
        XCTAssertFalse(page.contains("<script>alert"))
        XCTAssertTrue(page.contains("&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;"))
    }

    func testAppPageUsesRelativeEndpoints() {
        let page = TransferWebPage.app(deviceName: "i", libraryCount: 1)
        for needle in [
            "BASE + 'upload?name='",
            "BASE + 'state'",
            "BASE + 'library'",
            "BASE + 'cover/'",
            "BASE + 'download/'",
        ] {
            XCTAssertTrue(page.contains(needle), "missing \(needle)")
        }
        XCTAssertTrue(page.contains("var BASE = './';"))
    }

    func testAppPageHasNoPasswordUI() {
        let page = TransferWebPage.app(deviceName: "i", libraryCount: 1)
        XCTAssertFalse(page.contains("密码"))
        XCTAssertFalse(page.contains("id=\"code\""))
    }

    func testHtmlEscape() {
        XCTAssertEqual(
            TransferWebPage.htmlEscape("&<>\"'"),
            "&amp;&lt;&gt;&quot;&#39;"
        )
        XCTAssertEqual(TransferWebPage.htmlEscape("普通文本"), "普通文本")
    }
}
