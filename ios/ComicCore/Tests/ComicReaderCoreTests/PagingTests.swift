import XCTest
@testable import ComicReaderCore

// tests/unit/paging.test.ts 的移植

/// offset=1：封面单独占屏，之后 (1,2) (3,4)… 成对
let cover = SpreadContext(pageCount: 10, offset: 1)
/// offset=0：从第一页起两两成对
let paired = SpreadContext(pageCount: 10, offset: 0)

final class PagingTests: XCTestCase {
    // MARK: spreadAt

    func testSpreadAtCoverSingleThenPairs() {
        XCTAssertEqual(spreadAt(0, cover), [0])
        XCTAssertEqual(spreadAt(1, cover), [1, 2])
        XCTAssertEqual(spreadAt(2, cover), [1, 2])
        XCTAssertEqual(spreadAt(3, cover), [3, 4])
    }

    func testSpreadAtPairedFromFirstPage() {
        XCTAssertEqual(spreadAt(0, paired), [0, 1])
        XCTAssertEqual(spreadAt(1, paired), [0, 1])
        XCTAssertEqual(spreadAt(2, paired), [2, 3])
    }

    func testSpreadAtOddLastPageAlone() {
        let odd = SpreadContext(pageCount: 4, offset: 1)
        XCTAssertEqual(spreadAt(3, odd), [3])
    }

    func testSpreadAtWidePageShiftsPairing() {
        let ctx = SpreadContext(pageCount: 8, offset: 1, isWide: { $0 == 3 })
        XCTAssertEqual(spreadAt(1, ctx), [1, 2])
        XCTAssertEqual(spreadAt(3, ctx), [3])
        // 跨页把节奏推后一位：原本的 (3,4) 变成 (4,5)
        XCTAssertEqual(spreadAt(4, ctx), [4, 5])
        XCTAssertEqual(spreadAt(6, ctx), [6, 7])
    }

    func testSpreadAtWidePageNotPulledIntoOthers() {
        let ctx = SpreadContext(pageCount: 6, offset: 0, isWide: { $0 == 1 })
        XCTAssertEqual(spreadAt(0, ctx), [0])
        XCTAssertEqual(spreadAt(1, ctx), [1])
        XCTAssertEqual(spreadAt(2, ctx), [2, 3])
    }

    func testSpreadAtClampsAndEmptyBook() {
        XCTAssertEqual(spreadAt(999, cover), [9])
        XCTAssertEqual(spreadAt(-5, cover), [0])
        XCTAssertEqual(spreadAt(0, SpreadContext(pageCount: 0, offset: 1)), [])
    }

    // MARK: stepSpread

    func testStepSpreadForwardAndBackward() {
        XCTAssertEqual(stepSpread(0, 1, cover), 1)
        XCTAssertEqual(stepSpread(1, 1, cover), 3)
        XCTAssertEqual(stepSpread(3, -1, cover), 1)
        XCTAssertEqual(stepSpread(1, -1, cover), 0)
    }

    func testStepSpreadStaysAtEnds() {
        XCTAssertEqual(stepSpread(0, -1, cover), 0)
        // 屏：[0] [1,2] [3,4]
        let last = SpreadContext(pageCount: 5, offset: 1)
        XCTAssertEqual(stepSpread(4, 1, last), 3)
    }

    func testStepSpreadWithWidePage() {
        let ctx = SpreadContext(pageCount: 8, offset: 1, isWide: { $0 == 3 })
        XCTAssertEqual(stepSpread(1, 1, ctx), 3)
        XCTAssertEqual(stepSpread(3, 1, ctx), 4)
        XCTAssertEqual(stepSpread(4, -1, ctx), 3)
    }

    func testStepSpreadEmptyBookDoesNotCrash() {
        XCTAssertEqual(stepSpread(0, 1, SpreadContext(pageCount: 0, offset: 0)), 0)
    }

    // MARK: isLastSpread

    func testIsLastSpread() {
        XCTAssertTrue(isLastSpread(9, cover))
        XCTAssertFalse(isLastSpread(7, cover))
        // 10 页 + 封面单独：最后一屏是 [9]
        XCTAssertFalse(isLastSpread(8, cover))
    }

    func testIsLastSpreadEmptyBookIsEnd() {
        XCTAssertTrue(isLastSpread(0, SpreadContext(pageCount: 0, offset: 1)))
    }

    // MARK: isWideSize

    func testIsWideSize() {
        XCTAssertTrue(isWideSize(width: 2000, height: 1400))
        XCTAssertFalse(isWideSize(width: 1400, height: 2000))
        XCTAssertFalse(isWideSize(width: 1000, height: 1000))
        XCTAssertFalse(isWideSize(width: 0, height: 0))
    }
}
