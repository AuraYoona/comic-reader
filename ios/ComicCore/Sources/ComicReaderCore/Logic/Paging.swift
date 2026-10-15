import Foundation

// MARK: - 双页模式的分屏计算（src/shared/paging.ts 的逐行移植）
//
// 两个规则叠加：
//   1. 配对偏移：offset == 1 时第一页（封面）单独占屏，之后两两成对；
//   2. 跨页大图：横向的跨页图独占整屏，不塞进半个视口。
//
// 跨页信息来自图片加载后的实际尺寸，未加载的页一律当作普通页。
// 某一页加载后被判定为跨页时，它之后的配对会顺延一位——
// 这正是「跨页图接管整屏」的预期表现，且只影响当前屏之后的排布。

/// 宽高比超过这个值就认为是跨页图
public let WIDE_PAGE_RATIO: Double = 1.2

public func isWideSize(width: Double, height: Double) -> Bool {
    width > 0 && height > 0 && width / height >= WIDE_PAGE_RATIO
}

public struct SpreadContext: Sendable {
    public let pageCount: Int
    /// 双页配对偏移：1 = 封面单独占屏；0 = 从第一页起两两成对
    public let offset: Int
    /// 页码是否为跨页图；nil 表示全部按普通页处理
    public let isWide: ((Int) -> Bool)?

    public init(pageCount: Int, offset: Int, isWide: ((Int) -> Bool)? = nil) {
        self.pageCount = pageCount
        self.offset = offset
        self.isWide = isWide
    }
}

private func wideAt(_ ctx: SpreadContext, _ index: Int) -> Bool {
    ctx.isWide?(index) ?? false
}

/// 以 start 为首页的那一屏包含的页码
private func spreadFrom(_ start: Int, _ ctx: SpreadContext) -> [Int] {
    if wideAt(ctx, start) { return [start] }
    let second = start + 1
    if second < ctx.pageCount && !wideAt(ctx, second) { return [start, second] }
    return [start]
}

/// 依次产出每一屏。页数为 0 时不产出任何屏。
/// （Swift 没有生成器，用惰性序列保持同样的产出顺序与语义。）
private func walkSpreads(_ ctx: SpreadContext) -> AnySequence<[Int]> {
    AnySequence<[Int]> { () -> AnyIterator<[Int]> in
        let pageCount = ctx.pageCount
        var i = 0
        var started = false
        return AnyIterator {
            guard pageCount > 0 else { return nil }
            // 封面单独占屏
            if !started {
                started = true
                if ctx.offset == 1 {
                    i = 1
                    return [0]
                }
            }
            guard i < pageCount else { return nil }
            let spread = spreadFrom(i, ctx)
            i += spread.count
            return spread
        }
    }
}

private func clampPage(_ page: Int, _ pageCount: Int) -> Int {
    min(max(0, page), max(0, pageCount - 1))
}

/// 包含 page 的那一屏（页码升序，1 或 2 页）。页数为 0 时返回空数组。
public func spreadAt(_ page: Int, _ ctx: SpreadContext) -> [Int] {
    if ctx.pageCount <= 0 { return [] }
    let target = clampPage(page, ctx.pageCount)
    for spread in walkSpreads(ctx) {
        if spread[spread.count - 1] >= target { return spread }
    }
    return [target]
}

/// 相邻一屏的首页；已经在首屏 / 末屏时返回当前屏的首页。
/// dir = 1 下一屏，dir = -1 上一屏。
public func stepSpread(_ page: Int, _ dir: Int, _ ctx: SpreadContext) -> Int {
    if ctx.pageCount <= 0 { return 0 }
    let target = clampPage(page, ctx.pageCount)
    var prevStart = -1
    var found: [Int]? = nil
    for spread in walkSpreads(ctx) {
        if found != nil {
            return dir == 1 ? spread[0] : found![0]
        }
        if spread[spread.count - 1] >= target {
            found = spread
            if dir == -1 { return prevStart >= 0 ? prevStart : spread[0] }
        } else {
            prevStart = spread[0]
        }
    }
    // 已是最后一屏
    return found?[0] ?? target
}

/// 当前屏是否已经是最后一屏
public func isLastSpread(_ page: Int, _ ctx: SpreadContext) -> Bool {
    if ctx.pageCount <= 0 { return true }
    let spread = spreadAt(page, ctx)
    return spread.isEmpty || spread[spread.count - 1] >= ctx.pageCount - 1
}
