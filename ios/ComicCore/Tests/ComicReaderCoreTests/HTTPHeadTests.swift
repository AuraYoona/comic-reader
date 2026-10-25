import XCTest
@testable import ComicReaderCore

// HTTPRequestHeadParser：请求行 / headers / framing / 上限 / 攻击样例

final class HTTPHeadTests: XCTestCase {
    private func parse(_ text: String) -> HTTPHeadParseResult {
        HTTPRequestHeadParser.parse(Data(text.utf8))
    }

    private func completeHead(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> HTTPRequestHead {
        guard case .complete(let head, _) = parse(text) else {
            XCTFail("expected complete head", file: file, line: line)
            return HTTPRequestHead(method: "", target: "")
        }
        return head
    }

    func testSimpleGet() {
        let text = "GET /123456/ HTTP/1.1\r\nHost: 192.168.1.5:8765\r\n\r\n"
        guard case .complete(let head, let consumed) = parse(text) else {
            return XCTFail("expected complete")
        }
        XCTAssertEqual(head.method, "GET")
        XCTAssertEqual(head.target, "/123456/")
        XCTAssertEqual(head.version, "HTTP/1.1")
        XCTAssertEqual(head.header("host"), "192.168.1.5:8765")
        XCTAssertEqual(head.framing, HTTPBodyFraming.none)
        XCTAssertFalse(head.expectsContinue)
        XCTAssertEqual(consumed, Data(text.utf8).count)
    }

    func testHeaderNamesAreCaseInsensitiveAndMerged() {
        let text = "GET / HTTP/1.1\r\nX-Test: 1\r\nx-test: 2\r\n\r\n"
        let head = completeHead(text)
        XCTAssertEqual(head.header("X-Test"), "1, 2")
        XCTAssertEqual(head.headers["x-test"], "1, 2")
    }

    func testContentLengthAndBodyRemainder() {
        let text = "POST /upload?name=a.cbz HTTP/1.1\r\nContent-Length: 12\r\n\r\nhello"
        let data = Data(text.utf8)
        guard case .complete(let head, let consumed) = HTTPRequestHeadParser.parse(data) else {
            return XCTFail("expected complete")
        }
        XCTAssertEqual(head.framing, HTTPBodyFraming.contentLength(12))
        XCTAssertEqual(data.count - consumed, 5)
        XCTAssertEqual(String(decoding: data[consumed...], as: UTF8.self), "hello")
    }

    func testZeroContentLength() {
        let head = completeHead("PUT /x HTTP/1.1\r\nContent-Length: 0\r\n\r\n")
        XCTAssertEqual(head.framing, HTTPBodyFraming.contentLength(0))
    }

    func testChunked() {
        let head = completeHead("PUT /x HTTP/1.1\r\nTransfer-Encoding: Chunked\r\n\r\n")
        XCTAssertEqual(head.framing, HTTPBodyFraming.chunked)
    }

    func testChunkedWithIdentityPrefix() {
        let head = completeHead("PUT /x HTTP/1.1\r\nTransfer-Encoding: identity, chunked\r\n\r\n")
        XCTAssertEqual(head.framing, HTTPBodyFraming.chunked)
    }

    func testUnsupportedTransferEncoding() {
        XCTAssertEqual(
            parse("PUT /x HTTP/1.1\r\nTransfer-Encoding: gzip\r\n\r\n"),
            .failure(.unsupportedTransferEncoding)
        )
        XCTAssertEqual(
            parse("PUT /x HTTP/1.1\r\nTransfer-Encoding: gzip, chunked\r\n\r\n"),
            .failure(.unsupportedTransferEncoding)
        )
    }

    func testTransferEncodingAndContentLengthConflict() {
        XCTAssertEqual(
            parse("PUT /x HTTP/1.1\r\nTransfer-Encoding: chunked\r\nContent-Length: 5\r\n\r\n"),
            .failure(.ambiguousBodyFraming)
        )
    }

    func testConflictingDuplicateContentLength() {
        XCTAssertEqual(
            parse("PUT /x HTTP/1.1\r\nContent-Length: 5\r\nContent-Length: 6\r\n\r\n"),
            .failure(.conflictingContentLength)
        )
    }

    func testSameDuplicateContentLengthIsAccepted() {
        let head = completeHead("PUT /x HTTP/1.1\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\n")
        XCTAssertEqual(head.framing, HTTPBodyFraming.contentLength(5))
    }

    func testInvalidContentLength() {
        for value in ["abc", "-1", "1 2", "0x10", ""] {
            XCTAssertEqual(
                parse("PUT /x HTTP/1.1\r\nContent-Length: \(value)\r\n\r\n"),
                .failure(.invalidContentLength),
                "value: \(value)"
            )
        }
    }

    func testExpectContinue() {
        XCTAssertTrue(completeHead("PUT /x HTTP/1.1\r\nExpect: 100-Continue\r\n\r\n").expectsContinue)
        XCTAssertFalse(completeHead("PUT /x HTTP/1.1\r\nExpect: something\r\n\r\n").expectsContinue)
    }

    func testIncompleteHead() {
        XCTAssertEqual(parse("GET / HTTP/1.1\r\nHost: x\r\n"), .incomplete)
        XCTAssertEqual(parse(""), .incomplete)
    }

    func testHeadTooLarge() {
        let huge = "GET / HTTP/1.1\r\nX: " + String(repeating: "a", count: HTTPLimits.maxHeadBytes + 10)
        XCTAssertEqual(parse(huge), .failure(.headTooLarge))
    }

    func testLfOnlyLineEndings() {
        let head = completeHead("GET /abc HTTP/1.0\nHost: x\n\n")
        XCTAssertEqual(head.method, "GET")
        XCTAssertEqual(head.target, "/abc")
        XCTAssertEqual(head.version, "HTTP/1.0")
        XCTAssertEqual(head.header("host"), "x")
    }

    func testMalformedRequestLines() {
        XCTAssertEqual(parse("\r\n\r\n"), .failure(.malformedRequestLine))
        XCTAssertEqual(parse("GET /\r\n\r\n"), .failure(.malformedRequestLine))
        XCTAssertEqual(parse("GET / HTTP/2.0\r\n\r\n"), .failure(.unsupportedVersion))
        XCTAssertEqual(parse("GET http://x/ HTTP/1.1\r\n\r\n"), .failure(.malformedRequestLine))
        XCTAssertEqual(parse("G@T / HTTP/1.1\r\n\r\n"), .failure(.malformedRequestLine))
    }

    func testMalformedHeader() {
        XCTAssertEqual(
            parse("GET / HTTP/1.1\r\nNoColon\r\n\r\n"),
            .failure(.malformedHeader)
        )
        XCTAssertEqual(
            parse("GET / HTTP/1.1\r\nBad Name: x\r\n\r\n"),
            .failure(.malformedHeader)
        )
    }

    func testHeaderValueIsTrimmed() {
        let head = completeHead("GET / HTTP/1.1\r\nX:   padded value   \r\n\r\n")
        XCTAssertEqual(head.header("x"), "padded value")
    }

    func testConsumedStopsExactlyAfterBlankLine() {
        let text = "GET / HTTP/1.1\r\nA: b\r\n\r\nBODY"
        let data = Data(text.utf8)
        guard case .complete(_, let consumed) = HTTPRequestHeadParser.parse(data) else {
            return XCTFail("expected complete")
        }
        XCTAssertEqual(String(decoding: data[consumed...], as: UTF8.self), "BODY")
    }

    func testEarliestTerminatorWinsForLfHeadWithBinaryBody() {
        // LF 换行的请求头 + 二进制 body 里恰好出现 CRLFCRLF：不能被当成请求头结束
        let text = "PUT /x HTTP/1.1\nContent-Length: 8\n\nAB\r\n\r\nCD"
        let data = Data(text.utf8)
        guard case .complete(let head, let consumed) = HTTPRequestHeadParser.parse(data) else {
            return XCTFail("expected complete")
        }
        XCTAssertEqual(head.framing, HTTPBodyFraming.contentLength(8))
        XCTAssertEqual(String(decoding: data[consumed...], as: UTF8.self), "AB\r\n\r\nCD")
    }

    func testEarliestTerminatorWinsForCrlfHeadWithLfBody() {
        let text = "PUT /x HTTP/1.1\r\nContent-Length: 4\r\n\r\nA\n\nB"
        let data = Data(text.utf8)
        guard case .complete(_, let consumed) = HTTPRequestHeadParser.parse(data) else {
            return XCTFail("expected complete")
        }
        XCTAssertEqual(String(decoding: data[consumed...], as: UTF8.self), "A\n\nB")
    }
}
