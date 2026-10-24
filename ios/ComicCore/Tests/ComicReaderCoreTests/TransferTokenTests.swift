import XCTest
@testable import ComicReaderCore

// TransferToken：6 位数字、可注入随机源、常量时间比较

final class TransferTokenTests: XCTestCase {
    private struct SeededRNG: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    func testGeneratedTokensAreSixDigits() {
        for _ in 0..<200 {
            let token = TransferToken.generate()
            XCTAssertEqual(token.count, 6, token)
            XCTAssertTrue(token.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }, token)
            XCTAssertTrue(TransferToken.isWellFormed(token))
        }
    }

    func testDeterministicWithSameSeed() {
        var a = SeededRNG(state: 42)
        var b = SeededRNG(state: 42)
        XCTAssertEqual(TransferToken.generate(using: &a), TransferToken.generate(using: &b))
    }

    func testWellFormed() {
        XCTAssertTrue(TransferToken.isWellFormed("000000"))
        XCTAssertTrue(TransferToken.isWellFormed("482913"))
        XCTAssertFalse(TransferToken.isWellFormed("48291"))
        XCTAssertFalse(TransferToken.isWellFormed("4829133"))
        XCTAssertFalse(TransferToken.isWellFormed("48291a"))
        XCTAssertFalse(TransferToken.isWellFormed(""))
        XCTAssertFalse(TransferToken.isWellFormed("１２３４５６")) // 全角数字
    }

    func testMatches() {
        XCTAssertTrue(TransferToken.matches("482913", expected: "482913"))
        XCTAssertFalse(TransferToken.matches("482914", expected: "482913"))
        XCTAssertFalse(TransferToken.matches("48291", expected: "482913"))
        XCTAssertFalse(TransferToken.matches("", expected: "482913"))
    }
}
