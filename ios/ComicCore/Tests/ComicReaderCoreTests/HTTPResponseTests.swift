import XCTest
@testable import ComicReaderCore

// HTTPResponseHead：状态行、Content-Length、CRLF 注入防护

final class HTTPResponseTests: XCTestCase {
    private func text(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    func testBasicResponse() {
        let head = text(HTTPResponseHead.serialize(
            status: .ok,
            headers: [("Content-Type", "application/json")],
            contentLength: 2
        ))
        XCTAssertEqual(
            head,
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n"
        )
    }

    func testExplicitContentLengthIsNotDuplicated() {
        let head = text(HTTPResponseHead.serialize(
            status: .ok,
            headers: [("content-length", "7")],
            contentLength: 7
        )).lowercased()
        XCTAssertEqual(head.components(separatedBy: "content-length").count - 1, 1)
        XCTAssertTrue(head.contains("content-length: 7"))
    }

    func testCRLFInjectionIsStripped() {
        let head = text(HTTPResponseHead.serialize(
            status: .ok,
            headers: [("X-Test", "ok\r\nX-Evil: 1")],
            contentLength: 0
        ))
        XCTAssertTrue(head.contains("X-Test: okX-Evil: 1"))
        XCTAssertTrue(head.hasSuffix("\r\n\r\n"))
        XCTAssertEqual(head.components(separatedBy: "\r\n").filter { $0.hasPrefix("X-Evil") }.count, 0)
    }

    func testContinueResponse() {
        XCTAssertEqual(text(HTTPResponseHead.continueResponse), "HTTP/1.1 100 Continue\r\n\r\n")
    }

    func testStatusReasons() {
        XCTAssertEqual(HTTPStatus.forbidden.rawValue, 403)
        XCTAssertEqual(HTTPStatus.insufficientStorage.rawValue, 507)
        XCTAssertEqual(HTTPStatus.insufficientStorage.reason, "Insufficient Storage")
    }
}
