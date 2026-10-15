import Foundation

// MARK: - 自动裁白边（src/shared/crop.ts 的逐行移植）
//
// 扫描版漫画常带一圈纯色留白，双页对齐和「适应宽度」都会被它拖累。
// 这里只做最稳妥的判断：以四角颜色作为背景色，从各边向内推进，
// 只要整行/整列都接近背景色就继续裁，遇到内容立刻停。

public struct CropInsets: Equatable, Sendable {
    /// 0–1 之间的比例
    public var top: Double
    public var right: Double
    public var bottom: Double
    public var left: Double

    public init(top: Double, right: Double, bottom: Double, left: Double) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    public static let noCrop = CropInsets(top: 0, right: 0, bottom: 0, left: 0)
}

public let CROP_TOLERANCE = 18
public let CROP_CORNER_TOLERANCE = 24
public let CROP_MAX_INSET = 0.25
public let CROP_MIN_MEANINGFUL = 0.01

public func hasCrop(_ insets: CropInsets?) -> Bool {
    guard let insets else { return false }
    return insets.top + insets.right + insets.bottom + insets.left > 0
}

typealias Rgb = (r: UInt8, g: UInt8, b: UInt8)

private func pixelAt(_ data: [UInt8], _ width: Int, _ x: Int, _ y: Int) -> Rgb {
    let i = (y * width + x) * 4
    return (data[i], data[i + 1], data[i + 2])
}

private func diff(_ a: Rgb, _ b: Rgb) -> Int {
    let dr = abs(Int(a.r) - Int(b.r))
    let dg = abs(Int(a.g) - Int(b.g))
    let db = abs(Int(a.b) - Int(b.b))
    return max(dr, max(dg, db))
}

/// 四角平均色；四角互相差太多则返回 nil（例如跨页拼图、带花边的扫图）
private func backgroundColor(_ data: [UInt8], _ width: Int, _ height: Int) -> Rgb? {
    let corners = [
        pixelAt(data, width, 0, 0),
        pixelAt(data, width, width - 1, 0),
        pixelAt(data, width, 0, height - 1),
        pixelAt(data, width, width - 1, height - 1)
    ]
    for i in 1..<corners.count {
        if diff(corners[0], corners[i]) > CROP_CORNER_TOLERANCE { return nil }
    }
    let r = corners.map { Int($0.r) }.reduce(0, +) / 4
    let g = corners.map { Int($0.g) }.reduce(0, +) / 4
    let b = corners.map { Int($0.b) }.reduce(0, +) / 4
    return (UInt8(r), UInt8(g), UInt8(b))
}

private func rowIsBackground(
    _ data: [UInt8], _ width: Int, _ y: Int, _ bg: Rgb, _ fromX: Int, _ toX: Int
) -> Bool {
    var x = fromX
    while x <= toX {
        if diff(pixelAt(data, width, x, y), bg) > CROP_TOLERANCE { return false }
        x += 1
    }
    return true
}

private func colIsBackground(
    _ data: [UInt8], _ width: Int, _ x: Int, _ bg: Rgb, _ fromY: Int, _ toY: Int
) -> Bool {
    var y = fromY
    while y <= toY {
        if diff(pixelAt(data, width, x, y), bg) > CROP_TOLERANCE { return false }
        y += 1
    }
    return true
}

/// 从 RGBA 采样数据算出裁剪比例。
/// 返回 nil 表示不需要裁（没有统一背景、或留白少到没有意义）。
public func computeCropInsets(data: [UInt8], width: Int, height: Int) -> CropInsets? {
    if width < 4 || height < 4 || data.count < width * height * 4 { return nil }
    guard let bg = backgroundColor(data, width, height) else { return nil }

    let maxY = Int(Double(height) * CROP_MAX_INSET)
    let maxX = Int(Double(width) * CROP_MAX_INSET)

    var top = 0
    while top < maxY && rowIsBackground(data, width, top, bg, 0, width - 1) { top += 1 }
    var bottom = 0
    while bottom < maxY && rowIsBackground(data, width, height - 1 - bottom, bg, 0, width - 1) {
        bottom += 1
    }
    // 左右扫描时跳过已判定为留白的上下部分，避免被它们干扰
    let innerTop = top
    let innerBottom = height - 1 - bottom
    if innerTop >= innerBottom { return nil }

    var left = 0
    while left < maxX && colIsBackground(data, width, left, bg, innerTop, innerBottom) { left += 1 }
    var right = 0
    while right < maxX && colIsBackground(data, width, width - 1 - right, bg, innerTop, innerBottom) {
        right += 1
    }

    let insets = CropInsets(
        top: Double(top) / Double(height),
        bottom: Double(bottom) / Double(height),
        left: Double(left) / Double(width),
        right: Double(right) / Double(width)
    )
    // 四边都顶到上限：多半是整页空白或纯色页，裁了没有意义，保持原样更安全
    if top >= maxY && bottom >= maxY && left >= maxX && right >= maxX { return nil }
    let total = insets.top + insets.bottom + insets.left + insets.right
    if total < CROP_MIN_MEANINGFUL { return nil }
    // 兜底：万一整张图都是背景色，不要裁成 0 尺寸
    if insets.top + insets.bottom >= 1 || insets.left + insets.right >= 1 { return nil }
    return insets
}
