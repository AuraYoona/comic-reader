import XCTest
@testable import ComicReaderCore

// HTTPChunkedDecoder：任意字节边界、trailers、错误分支

final class HTTPChunkedTests: XCTestCase {
    private func drain(_ decoder: inout HTTPChunkedDecoder) -> (Data, Bool, HTTPChunkError?) {
        var out = Data()
        while true {
            switch decoder.next() {
            case .needMoreData:
                return (out, false, nil)
            case .data(let chunk):
                out.append(chunk)
            case .finished:
                return (out, true, nil)
            case .failure(let error):
                return (out, false, error)
            }
        }
    }

    private func decode(_ text: String) -> (Data, Bool, HTTPChunkError?) {
        var decoder = HTTPChunkedDecoder()
        decoder.append(Data(text.utf8))
        return drain(&decoder)
    }

    func testSingleChunk() {
        let result = decode("5\r\nhello\r\n0\r\n\r\n")
        XCTAssertEqual(String(decoding: result.0, as: UTF8.self), "hello")
        XCTAssertTrue(result.1)
        XCTAssertNil(result.2)
    }

    func testMultipleChunks() {
        let result = decode("5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n")
        XCTAssertEqual(String(decoding: result.0, as: UTF8.self), "hello world")
        XCTAssertTrue(result.1)
    }

    func testChunkExtensions() {
        let result = decode("5;name=value;x=1\r\nhello\r\n0\r\n\r\n")
        XCTAssertEqual(String(decoding: result.0, as: UTF8.self), "hello")
        XCTAssertTrue(result.1)
    }

    func testTrailers() {
        let result = decode("3\r\nabc\r\n0\r\nX-Trailer: yes\r\nX-Other: 2\r\n\r\n")
        XCTAssertEqual(String(decoding: result.0, as: UTF8.self), "abc")
        XCTAssertTrue(result.1)
    }

    func testZeroChunkOnly() {
        let result = decode("0\r\n\r\n")
        XCTAssertEqual(result.0.isEmpty, true)
        XCTAssertTrue(result.1)
    }

    func testBareLFTolerance() {
        let result = decode("5\nhello\n0\n\n")
        XCTAssertEqual(String(decoding: result.0, as: UTF8.self), "hello")
        XCTAssertTrue(result.1)
    }

    func testByteByByteFeeding() {
        let payload = "5\r\nhello\r\n6\r\n world\r\n0\r\nX-A: b\r\n\r\n"
        var decoder = HTTPChunkedDecoder()
        var out = Data()
        var finished = false
        for byte in Data(payload.utf8) {
            decoder.append(Data([byte]))
            let step = drain(&decoder)
            out.append(step.0)
            if let error = step.2 {
                return XCTFail("unexpected error: \(error)")
            }
            if step.1 {
                finished = true
                break
            }
        }
        XCTAssertEqual(String(decoding: out, as: UTF8.self), "hello world")
        XCTAssertTrue(finished)
    }

    func testEverySplitPoint() {
        let payload = Data("A\r\n0123456789\r\n3\r\nxyz\r\n0\r\n\r\n".utf8)
        for split in 0...payload.count {
            var decoder = HTTPChunkedDecoder()
            var out = Data()
            var finished = false

            decoder.append(payload.prefix(split))
            let first = drain(&decoder)
            out.append(first.0)
            if first.1 { finished = true }
            if let error = first.2 { return XCTFail("split \(split): \(error)") }

            if !finished {
                decoder.append(payload.suffix(payload.count - split))
                let second = drain(&decoder)
                out.append(second.0)
                if second.1 { finished = true }
                if let error = second.2 { return XCTFail("split \(split): \(error)") }
            }

            XCTAssertTrue(finished, "split \(split)")
            XCTAssertEqual(String(decoding: out, as: UTF8.self), "0123456789xyz", "split \(split)")
        }
    }

    func testInvalidChunkSize() {
        XCTAssertEqual(decode("Z\r\nhello\r\n").2, .invalidChunkSize)
        XCTAssertEqual(decode("\r\nhello\r\n").2, .invalidChunkSize)
    }

    func testChunkTooLarge() {
        // 0x80000000 = 2 GiB，超过 1 GiB 上限
        XCTAssertEqual(decode("80000000\r\n").2, .chunkTooLarge)
        // 超出 UInt64 的十六进制也按过大处理
        XCTAssertEqual(decode("FFFFFFFFFFFFFFFFFF\r\n").2, .chunkTooLarge)
    }

    func testMalformedChunkTerminator() {
        XCTAssertEqual(decode("1\r\naX0\r\n\r\n").2, .malformedChunkTerminator)
    }

    func testMalformedTrailer() {
        XCTAssertEqual(decode("0\r\nnocolon\r\n\r\n").2, .malformedTrailer)
    }

    func testLineTooLong() {
        var decoder = HTTPChunkedDecoder()
        decoder.append(Data(repeating: 97, count: HTTPLimits.maxChunkLineBytes + 100))
        XCTAssertEqual(drain(&decoder).2, .lineTooLong)
    }

    func testTrailingBytesAfterFinishAreIgnored() {
        let result = decode("0\r\n\r\nGARBAGE")
        XCTAssertTrue(result.1)
        XCTAssertTrue(result.0.isEmpty)
    }
}
