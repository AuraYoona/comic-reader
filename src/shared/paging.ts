import type { PageOffset } from './types'

/**
 * 双页模式的分屏计算（纯函数，可单独单元测试）。
 *
 * 两个规则叠加：
 *   1. 配对偏移：offset=1 时第一页（封面）单独占屏，之后两两成对；
 *   2. 跨页大图：横向的跨页图独占整屏，不塞进半个视口。
 *
 * 跨页信息来自图片加载后的实际尺寸，未加载的页一律当作普通页。
 * 某一页加载后被判定为跨页时，它之后的配对会顺延一位——
 * 这正是「跨页图接管整屏」的预期表现，且只影响当前屏之后的排布。
 */

/** 宽高比超过这个值就认为是跨页图 */
export const WIDE_PAGE_RATIO = 1.2

export function isWideSize(width: number, height: number): boolean {
  return width > 0 && height > 0 && width / height >= WIDE_PAGE_RATIO
}

export interface SpreadContext {
  pageCount: number
  offset: PageOffset
  /** 页码是否为跨页图；不传表示全部按普通页处理 */
  isWide?: (index: number) => boolean
}

function wideAt(ctx: SpreadContext, index: number): boolean {
  return ctx.isWide ? ctx.isWide(index) : false
}

/** 以 start 为首页的那一屏包含的页码 */
function spreadFrom(start: number, ctx: SpreadContext): number[] {
  if (wideAt(ctx, start)) return [start]
  const second = start + 1
  if (second < ctx.pageCount && !wideAt(ctx, second)) return [start, second]
  return [start]
}

/** 依次产出每一屏。页数为 0 时不产出任何屏。 */
function* walkSpreads(ctx: SpreadContext): Generator<number[]> {
  const { pageCount, offset } = ctx
  if (pageCount <= 0) return
  let i = 0
  // 封面单独占屏
  if (offset === 1) {
    yield [0]
    i = 1
  }
  while (i < pageCount) {
    const spread = spreadFrom(i, ctx)
    yield spread
    i += spread.length
  }
}

function clampPage(page: number, pageCount: number): number {
  if (!Number.isFinite(page)) return 0
  return Math.min(Math.max(0, Math.round(page)), Math.max(0, pageCount - 1))
}

/** 包含 page 的那一屏（页码升序，1 或 2 页）。页数为 0 时返回空数组。 */
export function spreadAt(page: number, ctx: SpreadContext): number[] {
  if (ctx.pageCount <= 0) return []
  const target = clampPage(page, ctx.pageCount)
  for (const spread of walkSpreads(ctx)) {
    if (spread[spread.length - 1] >= target) return spread
  }
  return [target]
}

/**
 * 相邻一屏的首页；已经在首屏 / 末屏时返回当前屏的首页。
 * dir = 1 下一屏，dir = -1 上一屏。
 */
export function stepSpread(page: number, dir: 1 | -1, ctx: SpreadContext): number {
  if (ctx.pageCount <= 0) return 0
  const target = clampPage(page, ctx.pageCount)
  let prevStart = -1
  let found: number[] | null = null
  for (const spread of walkSpreads(ctx)) {
    if (found) return dir === 1 ? spread[0] : found[0]
    if (spread[spread.length - 1] >= target) {
      found = spread
      if (dir === -1) return prevStart >= 0 ? prevStart : spread[0]
    } else {
      prevStart = spread[0]
    }
  }
  // 已是最后一屏
  return found ? found[0] : target
}

/** 当前屏是否已经是最后一屏 */
export function isLastSpread(page: number, ctx: SpreadContext): boolean {
  if (ctx.pageCount <= 0) return true
  const spread = spreadAt(page, ctx)
  return spread.length === 0 || spread[spread.length - 1] >= ctx.pageCount - 1
}
