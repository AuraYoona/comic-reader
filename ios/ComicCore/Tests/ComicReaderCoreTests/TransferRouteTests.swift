import XCTest
@testable import ComicReaderCore

// TransferRoute：密码即首段路径；查询串解码；未知路径保留密码便于区分 403/404

final class TransferRouteTests: XCTestCase {
    func testLanding() {
        XCTAssertEqual(TransferRoute.parse("/"), .landing)
        XCTAssertEqual(TransferRoute.parse("/?x=1"), .landing)
        XCTAssertEqual(TransferRoute.parse("//"), .landing)
        XCTAssertFalse(TransferRoute.parse("/").requiresToken)
    }

    func testPageWithAndWithoutTrailingSlash() {
        XCTAssertEqual(
            TransferRoute.parse("/482913/"),
            .page(token: "482913", trailingSlash: true)
        )
        XCTAssertEqual(
            TransferRoute.parse("/482913"),
            .page(token: "482913", trailingSlash: false)
        )
    }

    func testUploadWithoutName() {
        XCTAssertEqual(
            TransferRoute.parse("/482913/upload"),
            .upload(token: "482913", fileName: nil)
        )
    }

    func testUploadNameDecoding() {
        XCTAssertEqual(
            TransferRoute.parse("/482913/upload?name=One%20Piece%2001.cbz"),
            .upload(token: "482913", fileName: "One Piece 01.cbz")
        )
        XCTAssertEqual(
            TransferRoute.parse("/482913/upload?name=%E6%BC%AB%E7%94%BB%2001.cbz"),
            .upload(token: "482913", fileName: "漫画 01.cbz")
        )
        // 表单编码：+ 是空格，%2B 才是加号
        XCTAssertEqual(
            TransferRoute.parse("/482913/upload?name=a+b.cbz"),
            .upload(token: "482913", fileName: "a b.cbz")
        )
        XCTAssertEqual(
            TransferRoute.parse("/482913/upload?name=a%2Bb.cbz"),
            .upload(token: "482913", fileName: "a+b.cbz")
        )
    }

    func testUploadIgnoresOtherQueryParameters() {
        XCTAssertEqual(
            TransferRoute.parse("/482913/upload?foo=1&name=x.cbz&bar=2"),
            .upload(token: "482913", fileName: "x.cbz")
        )
    }

    func testOtherRoutes() {
        XCTAssertEqual(TransferRoute.parse("/482913/state"), .state(token: "482913"))
        XCTAssertEqual(TransferRoute.parse("/482913/library"), .library(token: "482913"))
        XCTAssertEqual(
            TransferRoute.parse("/482913/cover/abc-123"),
            .cover(token: "482913", id: "abc-123")
        )
        XCTAssertEqual(
            TransferRoute.parse("/482913/download/abc-123"),
            .download(token: "482913", id: "abc-123")
        )
        XCTAssertEqual(
            TransferRoute.parse("/482913/download/a%20b"),
            .download(token: "482913", id: "a b")
        )
    }

    func testUnknownPathKeepsToken() {
        XCTAssertEqual(
            TransferRoute.parse("/482913/nope"),
            .notFound(token: "482913")
        )
        XCTAssertEqual(
            TransferRoute.parse("/482913/library/extra"),
            .notFound(token: "482913")
        )
        XCTAssertEqual(
            TransferRoute.parse("/482913/cover"),
            .notFound(token: "482913")
        )
    }

    func testBadPercentEncoding() {
        XCTAssertEqual(TransferRoute.parse("/%ZZ/"), .notFound(token: nil))
        XCTAssertEqual(TransferRoute.parse("/482913/upload?name=%ZZ"), .upload(token: "482913", fileName: nil))
    }

    func testTokenTooLong() {
        let token = String(repeating: "1", count: 65)
        XCTAssertEqual(TransferRoute.parse("/\(token)/"), .notFound(token: nil))
    }

    func testFragmentIsDropped() {
        XCTAssertEqual(
            TransferRoute.parse("/482913/library#section"),
            .library(token: "482913")
        )
    }

    func testRequiresToken() {
        XCTAssertTrue(TransferRoute.parse("/482913/").requiresToken)
        XCTAssertTrue(TransferRoute.parse("/482913/library").requiresToken)
        XCTAssertFalse(TransferRoute.parse("/").requiresToken)
    }

    func testQueryValueDirectly() {
        XCTAssertEqual(TransferRoute.queryValue("a=1&b=two%20words", key: "b"), "two words")
        XCTAssertNil(TransferRoute.queryValue("a=1", key: "b"))
        XCTAssertNil(TransferRoute.queryValue("a", key: "a"))
    }
}
