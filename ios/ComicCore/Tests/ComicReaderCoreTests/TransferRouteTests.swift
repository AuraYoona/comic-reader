import XCTest
@testable import ComicReaderCore

// TransferRoute：无密码设计，路径首段即接口；查询串解码

final class TransferRouteTests: XCTestCase {
    func testLanding() {
        XCTAssertEqual(TransferRoute.parse("/"), .landing)
        XCTAssertEqual(TransferRoute.parse("/?x=1"), .landing)
        XCTAssertEqual(TransferRoute.parse("//"), .landing)
    }

    func testUploadWithoutName() {
        XCTAssertEqual(TransferRoute.parse("/upload"), .upload(fileName: nil))
    }

    func testUploadNameDecoding() {
        XCTAssertEqual(
            TransferRoute.parse("/upload?name=One%20Piece%2001.cbz"),
            .upload(fileName: "One Piece 01.cbz")
        )
        XCTAssertEqual(
            TransferRoute.parse("/upload?name=%E6%BC%AB%E7%94%BB%2001.cbz"),
            .upload(fileName: "漫画 01.cbz")
        )
        // 表单编码：+ 是空格，%2B 才是加号
        XCTAssertEqual(
            TransferRoute.parse("/upload?name=a+b.cbz"),
            .upload(fileName: "a b.cbz")
        )
        XCTAssertEqual(
            TransferRoute.parse("/upload?name=a%2Bb.cbz"),
            .upload(fileName: "a+b.cbz")
        )
    }

    func testUploadIgnoresOtherQueryParameters() {
        XCTAssertEqual(
            TransferRoute.parse("/upload?foo=1&name=x.cbz&bar=2"),
            .upload(fileName: "x.cbz")
        )
    }

    func testOtherRoutes() {
        XCTAssertEqual(TransferRoute.parse("/state"), .state)
        XCTAssertEqual(TransferRoute.parse("/library"), .library)
        XCTAssertEqual(TransferRoute.parse("/cover/abc-123"), .cover(id: "abc-123"))
        XCTAssertEqual(TransferRoute.parse("/download/abc-123"), .download(id: "abc-123"))
        XCTAssertEqual(TransferRoute.parse("/download/a%20b"), .download(id: "a b"))
    }

    func testUnknownPaths() {
        XCTAssertEqual(TransferRoute.parse("/nope"), .notFound)
        XCTAssertEqual(TransferRoute.parse("/library/extra"), .notFound)
        XCTAssertEqual(TransferRoute.parse("/cover"), .notFound)
        // 无密码后路径首段是接口名，纯数字（旧二维码地址）是未知路径
        XCTAssertEqual(TransferRoute.parse("/482913/"), .notFound)
    }

    func testBadPercentEncoding() {
        XCTAssertEqual(TransferRoute.parse("/%ZZ/"), .notFound)
        XCTAssertEqual(TransferRoute.parse("/upload?name=%ZZ"), .upload(fileName: nil))
    }

    func testFragmentIsDropped() {
        XCTAssertEqual(TransferRoute.parse("/library#section"), .library)
    }

    func testQueryValueDirectly() {
        XCTAssertEqual(TransferRoute.queryValue("a=1&b=two%20words", key: "b"), "two words")
        XCTAssertNil(TransferRoute.queryValue("a=1", key: "b"))
        XCTAssertNil(TransferRoute.queryValue("a", key: "a"))
    }
}
