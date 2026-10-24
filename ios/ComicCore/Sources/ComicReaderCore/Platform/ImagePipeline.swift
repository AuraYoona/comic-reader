import Foundation

// MARK: - 图像管线（src/main/thumbnail.ts + coverThumbs.ts + autoCrop 采样链的移植）
//
// iOS 上 ImageIO 全能解码（WebP / AVIF / GIF / BMP），桌面版的
// 「原图直存 + 渲染进程 canvas 重压」两阶段在这里塌缩成一步。
// 常量与桌面版一致：封面 480px JPEG q0.82、页缩略图 180px q0.70、
// 裁边采样最长边 96px；都遵循「仅当更宽才缩放」，绝不放大。
//
// 整个文件用条件编译包住：Windows（本地类型检查）上被排除，
// iOS / macOS 上正常编译。

#if canImport(ImageIO) && canImport(CoreGraphics)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public struct ImagePipeline: Sendable {
    /// 封面目标宽度（thumbnail.ts COVER_WIDTH = 480）
    public static let coverWidth = 480
    /// 封面 JPEG 质量（thumbnail.ts COVER_JPEG_QUALITY = 82 → 0.82）
    public static let coverJpegQuality = 0.82
    /// 页缩略图目标宽度（thumbnail.ts PAGE_THUMB_WIDTH = 180）
    public static let pageThumbWidth = 180
    /// 页缩略图 JPEG 质量（thumbnail.ts PAGE_THUMB_QUALITY = 70 → 0.70）
    public static let pageThumbQuality = 0.7
    /// 裁边采样最长边（autoCrop.ts SAMPLE_MAX = 96）
    public static let cropSampleMax = 96

    // MARK: 封面 / 缩略图

    /// 封面：仅当原图宽 > 480 才缩放，再居中裁成 3:4（书架卡片即 3:4；
    /// 条漫/宽幅首页按宽度等比缩放会得到 480×N 的细长图，卡片里只能看到
    /// 一小截，解码后一张就要数 MB）；JPEG q0.82；解码失败返回 nil
    public static func makeCover(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        guard let image = scaledImage(from: source, maxWidth: coverWidth) else { return nil }
        return encodeJPEG(centerCropToCoverAspect(image), quality: coverJpegQuality)
    }

    /// 页缩略图：仅当原图宽 > 180 才缩放；JPEG q0.70（保持原始比例，
    /// 缩略图跳页条的槽位自己按 fill 裁）
    public static func makePageThumb(from data: Data) -> Data? {
        makeJPEG(from: data, maxWidth: pageThumbWidth, quality: pageThumbQuality)
    }

    /// 解码 → （必要时降采样）→ JPEG 编码
    private static func makeJPEG(from data: Data, maxWidth: Int, quality: Double) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        guard let image = scaledImage(from: source, maxWidth: maxWidth) else { return nil }
        return encodeJPEG(image, quality: quality)
    }

    private static func encodeJPEG(_ image: CGImage, quality: Double) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// 居中裁成 3:4；比例已在范围内或裁剪失败时原样返回
    private static func centerCropToCoverAspect(_ image: CGImage) -> CGImage {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return image }
        let targetW = min(w, h * 3 / 4)
        let targetH = min(h, w * 4 / 3)
        if targetW >= w, targetH >= h { return image }
        let rect = CGRect(
            x: (w - targetW) / 2, y: (h - targetH) / 2,
            width: targetW, height: targetH
        )
        return image.cropping(to: rect) ?? image
    }

    /// 取原图；宽超过 maxWidth 时按「宽度」比例降采样（不放大）。
    /// 注意 CGImageSourceCreateThumbnailAtIndex 的 maxPixelSize 约束的是**最长边**，
    /// 直接传 maxWidth 会让竖版图变得更窄——这里先按宽度算出比例，再换算成最长边上限。
    private static func scaledImage(from source: CGImageSource, maxWidth: Int) -> CGImage? {
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixelWidth = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let pixelHeight = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0

        if pixelWidth > 0, pixelWidth <= maxWidth {
            // 不放大：直接取原图
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }

        let maxDimension: Int
        if pixelWidth > 0, pixelHeight > 0 {
            // 宽度驱动的比例 → 最长边上限（结果宽度恰为 maxWidth）
            let scale = Double(maxWidth) / Double(pixelWidth)
            maxDimension = Int((Double(Swift.max(pixelWidth, pixelHeight)) * scale).rounded(.up))
        } else {
            // 尺寸未知：退化为最长边约束（桌面版此时依赖 nativeImage 自报的尺寸，等价近似）
            maxDimension = maxWidth
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: 阅读器解码

    /// 按最长边降采样解码（阅读器取图；绝不让 12MP 整图进内存）
    public static func downsample(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard maxPixelSize > 0 else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// 解码到 RGBA（裁边采样用）：最长边 ≤ maxPixel；行 0 = 图像顶部；失败 nil
    public static func rgbaSample(
        from data: Data, maxPixel: Int
    ) -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let image = downsample(data, maxPixelSize: maxPixel) else { return nil }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            // CGContext 默认原点在左下：翻转后行 0 = 图像顶部（与 canvas getImageData 一致）
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard success else { return nil }
        return (bytes, width, height)
    }

    // MARK: 裁白边

    /// 96px 降采样 → computeCropInsets（nil = 不需要裁 / 无法判定）
    public static func cropInsets(from data: Data) -> CropInsets? {
        guard let sample = rgbaSample(from: data, maxPixel: cropSampleMax) else { return nil }
        return computeCropInsets(data: sample.bytes, width: sample.width, height: sample.height)
    }
}
#endif
