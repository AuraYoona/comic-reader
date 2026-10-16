import Foundation
#if canImport(PDFKit)
import PDFKit
// CGImageDestination*（PNG 编码）在 ImageIO，PDFKit 不会转出该模块
import ImageIO
#endif

// MARK: - PDF 适配器（src/main/archive/pdf.ts 的移植）
//
// 页面以合成的 0001.png… 条目名暴露（固定 4 位，自然排序与页码一致；
// 阅读器只认图片扩展名）。渲染比例 PDF_RENDER_SCALE = 2（144 DPI），与桌面版一致。
// 桌面版常量：PDF_MAX_OPEN = 1、PDF_IDLE_MS = 45s、PDF_MAX_BYTES = 1.5 GiB。
// iOS 用 PDFKit（系统框架），渲染结果编码为 PNG 数据走统一图片管线。

#if canImport(PDFKit)
public final class PdfArchiveReader: ArchiveReader {
    /// 渲染比例（= 144 DPI），与桌面版 PDF_RENDER_SCALE 一致
    static let renderScale: CGFloat = 2
    /// 桌面版 PDF_MAX_BYTES：整个文件要载入内存，1.5 GiB 封顶
    static let maxBytes: Int = 1_610_612_736 // 1.5 * 1024 * 1024 * 1024

    private final class Handle {
        let document: PDFDocument
        init(document: PDFDocument) { self.document = document }
    }

    private let cache = HandleCache<Handle>(options: HandleCacheOptions<Handle>(
        max: 1,
        idleSeconds: 45,
        open: { path in
            let url = URL(fileURLWithPath: path)
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            let size = (attrs?[.size] as? Int) ?? 0
            // 注意：存储属性初始化器里不能引用协变 Self，用具体类名
            if size > PdfArchiveReader.maxBytes {
                throw SourceError("这个 PDF 超过 1.5 GB，渲染需要整体载入内存，暂不支持", path: path)
            }
            guard let document = PDFDocument(url: url) else {
                throw SourceError("无法识别的 PDF，文件可能已损坏或不是有效的 PDF", path: path)
            }
            if document.isLocked {
                throw SourceError("这个 PDF 有密码保护，暂不支持加密文件", path: path)
            }
            if document.pageCount <= 0 {
                throw SourceError("这个 PDF 里没有页面", path: path)
            }
            return Handle(document: document)
        },
        close: { _ in }
    ))

    public init() {}

    /// 固定 4 位，自然排序与页码一致；阅读器只认图片扩展名
    static func pageEntry(_ index: Int) -> String {
        String(format: "%04d.png", index + 1)
    }

    static func parsePageIndex(_ entry: String) -> Int? {
        guard let m = entry.range(of: #"^(\d+)\.png$"#, options: .regularExpression),
              let n = Int(entry[m].replacingOccurrences(of: ".png", with: "")) else { return nil }
        return n >= 1 ? n - 1 : nil
    }

    public func list(_ file: String) throws -> [ArchiveEntry] {
        let handle = try awaitBlocking { try await self.cache.acquire(file) }
        return (0..<handle.document.pageCount).map { i in
            ArchiveEntry(name: Self.pageEntry(i), isDirectory: false)
        }
    }

    public func read(_ file: String, entry: String) throws -> Data {
        guard let index = Self.parsePageIndex(entry) else {
            throw SourceError("PDF 中找不到这一页：\(entry)", path: file)
        }
        let handle = try awaitBlocking { try await self.cache.acquire(file) }
        guard let page = handle.document.page(at: index) else {
            throw SourceError("PDF 中找不到这一页：\(entry)", path: file)
        }
        guard let image = Self.render(page: page) else {
            throw SourceError("读取 PDF 失败，页面渲染为空", path: file)
        }
        guard let png = image.pngData() else {
            throw SourceError("读取 PDF 失败，页面编码失败", path: file)
        }
        return png
    }

    /// PDFPage → CGImage（2x 缩放，与桌面版 pdfium render 参数对齐）。
    /// 不用 thumbnail(of:for:)：它在 iOS 返回 UIImage、在 macOS 返回 NSImage，
    /// 取 CGImage 的方式不同；CGContext + page.draw 两端一致且白底可控
    /// （PDF 的透明区域在暗色阅读背景下会发黑）。
    static func render(page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let width = Int(bounds.width * Self.renderScale)
        let height = Int(bounds.height * Self.renderScale)
        guard width > 0, height > 0 else { return nil }

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        // 白底（与桌面版 pdfium 渲染出的不透明位图一致）
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        ctx.scaleBy(x: Self.renderScale, y: Self.renderScale)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    public func release(_ file: String) {
        cache.release(file)
    }

    public func releaseAll() {
        cache.releaseAll()
    }
}

extension CGImage {
    /// CGImage → PNG 字节（PDF 页渲染产物走统一图片管线）
    func pngData() -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, "public.png" as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, self, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
#endif
