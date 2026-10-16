import XCTest
@testable import ComicReaderCore

// ImagePipeline（封面 480/q0.82、缩略图 180/q0.70、降采样、裁边采样）
// 只在 Apple 平台编译与运行；Windows 类型检查时整体为空。

#if canImport(ImageIO) && canImport(CoreGraphics)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

final class ImagePipelineTests: XCTestCase {
    // MARK: 合成图工具

    /// 生成一张纯色 RGBA 图并编码为 PNG
    private func makePNG(width: Int, height: Int, color: (UInt8, UInt8, UInt8)) -> Data {
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(
            red: CGFloat(color.0) / 255,
            green: CGFloat(color.1) / 255,
            blue: CGFloat(color.2) / 255,
            alpha: 1
        )
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = ctx.makeImage()!

        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    /// 生成「白边 + 黑心」的图（border 像素宽的四周白边）
    private func makeBorderedPNG(size: Int, border: Int) -> Data {
        let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        ctx.setFillColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1)
        ctx.fill(CGRect(x: border, y: border, width: size - 2 * border, height: size - 2 * border))
        let image = ctx.makeImage()!

        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    private func decodeSize(_ data: Data) -> (width: Int, height: Int, uti: String?) {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let uti = CGImageSourceGetType(source) as String?
        return (image.width, image.height, uti)
    }

    // MARK: 封面

    func testCoverDownscalesWideImageTo480() {
        let png = makePNG(width: 1000, height: 800, color: (200, 30, 30))
        guard let jpeg = ImagePipeline.makeCover(from: png) else {
            return XCTFail("makeCover 不应失败")
        }
        // JPEG 魔数
        XCTAssertEqual(jpeg.prefix(3).map { $0 }, [0xFF, 0xD8, 0xFF])
        let size = decodeSize(jpeg)
        XCTAssertEqual(size.width, ImagePipeline.coverWidth)
        XCTAssertEqual(size.height, 384) // 1000:800 → 480:384
    }

    func testCoverDoesNotUpscaleNarrowImage() {
        let png = makePNG(width: 300, height: 200, color: (30, 200, 30))
        guard let jpeg = ImagePipeline.makeCover(from: png) else {
            return XCTFail("makeCover 不应失败")
        }
        XCTAssertEqual(decodeSize(jpeg).width, 300)
    }

    func testCoverIsWidthDrivenForPortraitImages() {
        // 竖版封面（漫画常态）：结果宽度应为 480、高度按比例（桌面版语义是
        // 「宽 > 480 才缩放」，不是「最长边 ≤ 480」）
        let png = makePNG(width: 800, height: 1200, color: (80, 80, 200))
        guard let jpeg = ImagePipeline.makeCover(from: png) else {
            return XCTFail("makeCover 不应失败")
        }
        let size = decodeSize(jpeg)
        XCTAssertEqual(size.width, ImagePipeline.coverWidth)
        XCTAssertEqual(size.height, 720) // 800:1200 → 480:720
    }

    func testCoverReturnsNilForGarbage() {
        XCTAssertNil(ImagePipeline.makeCover(from: Data([0x01, 0x02, 0x03])))
    }

    // MARK: 页缩略图

    func testPageThumbWidth180() {
        let png = makePNG(width: 1200, height: 1800, color: (20, 20, 200))
        guard let jpeg = ImagePipeline.makePageThumb(from: png) else {
            return XCTFail("makePageThumb 不应失败")
        }
        XCTAssertEqual(decodeSize(jpeg).width, ImagePipeline.pageThumbWidth)
    }

    // MARK: 降采样

    func testDownsampleLimitsMaxDimension() {
        let png = makePNG(width: 1000, height: 800, color: (128, 128, 128))
        guard let cg = ImagePipeline.downsample(png, maxPixelSize: 200) else {
            return XCTFail("downsample 不应失败")
        }
        XCTAssertEqual(max(cg.width, cg.height), 200)
    }

    // MARK: 裁边

    func testRgbaSampleShape() {
        let png = makePNG(width: 500, height: 400, color: (255, 255, 255))
        guard let sample = ImagePipeline.rgbaSample(from: png, maxPixel: 96) else {
            return XCTFail("rgbaSample 不应失败")
        }
        XCTAssertEqual(sample.bytes.count, sample.width * sample.height * 4)
        XCTAssertLessThanOrEqual(max(sample.width, sample.height), 96)
    }

    func testCropInsetsDetectsBorder() {
        // 400px 图、40px 白边 = 10%
        let png = makeBorderedPNG(size: 400, border: 40)
        guard let insets = ImagePipeline.cropInsets(from: png) else {
            return XCTFail("应识别出白边")
        }
        XCTAssertEqual(insets.top, 0.1, accuracy: 0.03)
        XCTAssertEqual(insets.bottom, 0.1, accuracy: 0.03)
        XCTAssertEqual(insets.left, 0.1, accuracy: 0.03)
        XCTAssertEqual(insets.right, 0.1, accuracy: 0.03)
    }

    func testCropInsetsNilForUniformImage() {
        let png = makePNG(width: 300, height: 300, color: (255, 255, 255))
        XCTAssertNil(ImagePipeline.cropInsets(from: png), "整页纯色不裁")
    }
}
#endif
