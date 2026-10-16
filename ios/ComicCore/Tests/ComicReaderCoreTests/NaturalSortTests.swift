import XCTest
@testable import ComicReaderCore

// tests/unit/naturalSort.test.ts 的移植

final class NaturalSortTests: XCTestCase {
    func testNumericOrdering() {
        XCTAssertEqual(naturalSort(["10.jpg", "1.jpg", "2.jpg"]), ["1.jpg", "2.jpg", "10.jpg"])
    }

    func testLeadingZerosAndMultiSegmentNumbers() {
        XCTAssertEqual(
            naturalSort(["p002.png", "p1.png", "p010.png"]),
            ["p1.png", "p002.png", "p010.png"]
        )
        XCTAssertEqual(
            naturalSort(["ch2/5.jpg", "ch2/10.jpg", "ch10/1.jpg", "ch1/1.jpg"]),
            ["ch1/1.jpg", "ch2/5.jpg", "ch2/10.jpg", "ch10/1.jpg"]
        )
    }

    func testCaseInsensitive() {
        XCTAssertEqual(naturalCompare("A.jpg", "a.jpg"), 0)
    }

    func testDoesNotMutateInput() {
        let input = ["2.jpg", "1.jpg"]
        _ = naturalSort(input)
        XCTAssertEqual(input, ["2.jpg", "1.jpg"])
    }

    // 顺带验证与桌面版一致的排序细节
    func testMixedNumberAndText() {
        // 数字段相同、后缀不同时按 zh locale 的字符串规则
        let sorted = naturalSort(["a10", "a9", "b1", "a1"])
        XCTAssertEqual(sorted.first, "a1")
        XCTAssertEqual(sorted.last, "b1")
    }

    func testStabilityOnEqualKeys() {
        // 相等键保持原顺序：x.jpg 与 X.jpg 比较相等，按原序 x 在前
        let sorted = naturalSort(["x.jpg", "X.jpg", "a.jpg"])
        XCTAssertEqual(sorted, ["a.jpg", "x.jpg", "X.jpg"])
    }
}
