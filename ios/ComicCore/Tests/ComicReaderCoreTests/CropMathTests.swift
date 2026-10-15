import XCTest
@testable import ComicReaderCore

// tests/unit/crop.test.ts 的移植

typealias Rgb = (r: UInt8, g: UInt8, b: UInt8)

let WHITE: Rgb = (255, 255, 255)
let BLACK: Rgb = (10, 10, 10)

/// 按 (x, y) → 颜色 生成一张 RGBA 采样图
func makeImage(
    _ width: Int, _ height: Int,
    paint: (Int, Int) -> Rgb
) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let (r, g, b) = paint(x, y)
            let i = (y * width + x) * 4
            data[i] = r
            data[i + 1] = g
            data[i + 2] = b
            data[i + 3] = 255
        }
    }
    return data
}

/// 四周留白 border 像素、中间是内容
func bordered(_ size: Int, _ border: Int, bg: Rgb = WHITE) -> [UInt8] {
    makeImage(size, size) { x, y in
        (x < border || y < border || x >= size - border || y >= size - border) ? bg : BLACK
    }
}

final class CropMathTests: XCTestCase {
    private func assertClose(_ a: Double, _ b: Double, accuracy: Double = 1e-5,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a, b, accuracy: accuracy, file: file, line: line)
    }

    func testFourSidedMargins() {
        let insets = computeCropInsets(data: bordered(40, 4), width: 40, height: 40)
        XCTAssertNotNil(insets)
        assertClose(insets!.top, 0.1)
        assertClose(insets!.bottom, 0.1)
        assertClose(insets!.left, 0.1)
        assertClose(insets!.right, 0.1)
    }

    func testBlackBackgroundMargins() {
        let size = 40
        let data = makeImage(size, size) { x, y in
            (x < 4 || y < 4 || x >= size - 4 || y >= size - 4) ? BLACK : WHITE
        }
        let insets = computeCropInsets(data: data, width: size, height: size)
        assertClose(insets!.top, 0.1)
    }

    func testOnlyLeftRightMargins() {
        let size = 40
        let data = makeImage(size, size) { x, _ in
            (x < 6 || x >= size - 6) ? WHITE : BLACK
        }
        let insets = computeCropInsets(data: data, width: size, height: size)
        XCTAssertEqual(insets!.top, 0)
        XCTAssertEqual(insets!.bottom, 0)
        assertClose(insets!.left, 0.15)
        assertClose(insets!.right, 0.15)
    }

    func testMarginOver25PercentGivesUp() {
        // 四边同时顶到上限会被当作空白页放弃裁剪
        let insets = computeCropInsets(data: bordered(40, 16), width: 40, height: 40)
        XCTAssertNil(insets)
    }

    func testInconsistentCornersGiveUp() {
        let size = 40
        let data = makeImage(size, size) { x, y in (x + y < size) ? WHITE : BLACK }
        XCTAssertNil(computeCropInsets(data: data, width: size, height: size))
    }

    func testNoMarginsReturnsNull() {
        let data = makeImage(40, 40) { x, y in
            (UInt8((x * 6) % 255), UInt8((y * 6) % 255), 128)
        }
        XCTAssertNil(computeCropInsets(data: data, width: 40, height: 40))
    }

    func testUniformPageNotCropped() {
        let data = makeImage(40, 40) { _, _ in WHITE }
        XCTAssertNil(computeCropInsets(data: data, width: 40, height: 40))
    }

    func testUnderOnePercentIgnoredAsNoise() {
        // 1px / 500px = 0.2% 每边，总计 0.8%
        XCTAssertNil(computeCropInsets(data: bordered(500, 1), width: 500, height: 500))
    }

    func testTooSmallOrIncompleteData() {
        XCTAssertNil(computeCropInsets(data: [UInt8](repeating: 0, count: 16), width: 2, height: 2))
        XCTAssertNil(computeCropInsets(data: [UInt8](repeating: 0, count: 16), width: 40, height: 40))
    }

    func testToleranceAllowsSlightNoise() {
        let size = 40
        let border = 4
        let data = makeImage(size, size) { x, y in
            if x < border || y < border || x >= size - border || y >= size - border {
                return (250, 252, 248) // 接近纯白，但不完全相等
            }
            return BLACK
        }
        let insets = computeCropInsets(data: data, width: size, height: size)
        assertClose(insets!.top, 0.1)
    }

    func testHasCrop() {
        XCTAssertFalse(hasCrop(nil))
        XCTAssertFalse(hasCrop(CropInsets(top: 0, right: 0, bottom: 0, left: 0)))
        XCTAssertTrue(hasCrop(CropInsets(top: 0.1, right: 0, bottom: 0, left: 0)))
    }
}
