import Foundation
import UIKit
import ComicReaderCore

// MARK: - 页面解码与缓存（替代桌面版的 comic:// + pageCache + protocol.ts 缩略图缓存）
//
// 桌面版：<img> 直接向 comic:// 请求整页字节，靠 Chromium 图像缓存 + img.decode() 预热
// （LRU 32 张）。iOS：一切经 ImagePipeline 降采样解码为 CGImage/UIImage——
// 绝不整图全分辨率进内存（12MP 页面会直接顶到 jetsam 上限）。
//
// 职责：
//   - 页面图：按「目标像素宽」降采样解码；LRU 32 张预取缓存；并发去重
//   - 页缩略图（78×108 槽位用）：180px JPEG q0.70 → 解码；24 MiB 字节预算，>512 KiB 不缓存
//     （对齐桌面版 protocol.ts 主进程缓存常量）
//   - 裁白边采样：96px 降采样 → computeCropInsets；缓存 400 条（对齐 autoCrop.ts MAX_CACHE）

@MainActor
final class PageProvider {
    /// 预取缓存张数（对齐桌面版 pageCache.ts MAX_ENTRIES = 32）
    static let pageCacheCount = 32
    /// 页缩略图缓存字节预算（对齐 protocol.ts THUMB_CACHE_MAX_BYTES = 24 MiB）
    static let thumbCacheBytes = 24 * 1024 * 1024
    /// 单张缩略图超过它就不缓存（对齐 protocol.ts THUMB_CACHEABLE_MAX_BYTES = 512 KiB）
    static let thumbCacheableMaxBytes = 512 * 1024
    /// 裁边结果缓存条数（对齐 autoCrop.ts MAX_CACHE = 400）
    static let cropCacheCount = 400

    private let pageCache = NSCache<NSString, UIImage>()
    private let thumbCache = NSCache<NSString, UIImage>()
    private var cropCache: [String: CropInsets?] = [:]
    private var cropOrder: [String] = []
    private var inflight: [String: Task<UIImage?, Never>] = [:]

    init() {
        pageCache.countLimit = Self.pageCacheCount
        thumbCache.totalCostLimit = Self.thumbCacheBytes
    }

    // MARK: 页面图

    /// 缓存命中直接返回（同步，供首帧无闪）
    func cachedPage(comic: Comic, index: Int) -> UIImage? {
        pageCache.object(forKey: key(comic, index))
    }

    /// 解码一页（带并发去重）；maxPixelSize = 目标最长边像素
    func page(comic: Comic, index: Int, maxPixelSize: Int) async -> UIImage? {
        let k = key(comic, index)
        if let hit = pageCache.object(forKey: k) { return hit }
        if let running = inflight[k] { return await running.value }

        let task = Task<UIImage?, Never> { [weak self] in
            let decoded: UIImage? = await Task.detached(priority: .userInitiated) {
                guard let bytes = try? readPage(comic, index: index),
                      let cg = ImagePipeline.downsample(bytes.data, maxPixelSize: maxPixelSize)
                else { return nil }
                return UIImage(cgImage: cg)
            }.value
            if let self, let decoded {
                self.pageCache.setObject(decoded, forKey: k)
            }
            self?.clearInflight(k)
            return decoded
        }
        inflight[k] = task
        return await task.value
    }

    /// 预取邻近页（offsets 由阅读器按模式传入，与桌面版一致：
    /// 单页 [1,2,-1,3]，双页 [2,3,-2,-1,4,5]）
    func prefetch(comic: Comic, current: Int, offsets: [Int], maxPixelSize: Int) {
        for offset in offsets {
            let index = current + offset
            guard index >= 0, index < comic.pageCount else { continue }
            let k = key(comic, index)
            if pageCache.object(forKey: k) != nil || inflight[k] != nil { continue }
            let task = Task<UIImage?, Never> { [weak self] in
                let decoded: UIImage? = await Task.detached(priority: .utility) {
                    guard let bytes = try? readPage(comic, index: index),
                          let cg = ImagePipeline.downsample(bytes.data, maxPixelSize: maxPixelSize)
                    else { return nil }
                    return UIImage(cgImage: cg)
                }.value
                if let self, let decoded {
                    self.pageCache.setObject(decoded, forKey: k)
                }
                self?.clearInflight(k)
                return decoded
            }
            inflight[k] = task
        }
    }

    // MARK: 页缩略图（缩略图跳页条）

    func thumbnail(comic: Comic, index: Int) async -> UIImage? {
        let k = key(comic, index)
        if let hit = thumbCache.object(forKey: k) { return hit }
        if let running = inflight["thumb:" + k] { return await running.value }

        let task = Task<UIImage?, Never> { [weak self] in
            let decoded: (image: UIImage, jpegBytes: Int)? = await Task.detached(priority: .utility) {
                guard let bytes = try? readPage(comic, index: index),
                      let jpeg = ImagePipeline.makePageThumb(from: bytes.data),
                      let image = UIImage(data: jpeg) else { return nil }
                return (image, jpeg.count)
            }.value
            if let self, let decoded {
                // 超过 512 KiB 的缩略图不缓存（对齐桌面版 protocol.ts）；成本 = 解码后占用
                if decoded.jpegBytes <= Self.thumbCacheableMaxBytes {
                    let cost = decoded.image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
                    self.thumbCache.setObject(decoded.image, forKey: k, cost: cost)
                }
            }
            self?.clearInflight("thumb:" + k)
            return decoded?.image
        }
        inflight["thumb:" + k] = task
        return await task.value
    }

    // MARK: 裁白边

    /// 缓存的裁边结果；nil 表示「已计算，不需要裁」
    func cachedCrop(comic: Comic, index: Int) -> CropInsets?? {
        cropCache[key(comic, index)]
    }

    /// 计算裁边（96px 采样；结果缓存 400 条，含「不需要裁」的否定结果）
    func cropInsets(comic: Comic, index: Int) async -> CropInsets? {
        let k = key(comic, index)
        if let hit = cropCache[k] { return hit }
        let insets: CropInsets? = await Task.detached(priority: .utility) {
            guard let bytes = try? readPage(comic, index: index) else { return nil }
            return ImagePipeline.cropInsets(from: bytes.data)
        }.value
        remember(k, insets)
        return insets
    }

    private func remember(_ k: String, _ insets: CropInsets?) {
        if cropCache[k] == nil {
            cropOrder.append(k)
        }
        cropCache[k] = insets
        if cropOrder.count > Self.cropCacheCount {
            let oldest = cropOrder.removeFirst()
            cropCache[oldest] = nil
        }
    }

    // MARK: 清理

    func clearAll() {
        pageCache.removeAllObjects()
        thumbCache.removeAllObjects()
        cropCache.removeAll()
        cropOrder.removeAll()
        inflight.removeAll()
    }

    func clearCropCache() {
        cropCache.removeAll()
        cropOrder.removeAll()
    }

    private func clearInflight(_ k: String) {
        inflight[k] = nil
    }

    private func key(_ comic: Comic, _ index: Int) -> NSString {
        "\(comic.id):\(index)" as NSString
    }
}
