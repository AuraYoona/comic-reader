import { describe, expect, it } from 'vitest'
import { computeCropInsets, hasCrop } from '../../src/shared/crop'

type Rgb = [number, number, number]

/** 按 (x, y) → 颜色 生成一张 RGBA 采样图 */
function makeImage(
  width: number,
  height: number,
  paint: (x: number, y: number) => Rgb
): Uint8ClampedArray {
  const data = new Uint8ClampedArray(width * height * 4)
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const [r, g, b] = paint(x, y)
      const i = (y * width + x) * 4
      data[i] = r
      data[i + 1] = g
      data[i + 2] = b
      data[i + 3] = 255
    }
  }
  return data
}

const WHITE: Rgb = [255, 255, 255]
const BLACK: Rgb = [10, 10, 10]

/** 四周留白 border 像素、中间是内容 */
function bordered(size: number, border: number, bg: Rgb = WHITE): Uint8ClampedArray {
  return makeImage(size, size, (x, y) =>
    x < border || y < border || x >= size - border || y >= size - border ? bg : BLACK
  )
}

describe('computeCropInsets', () => {
  it('算出四边留白的比例', () => {
    const insets = computeCropInsets(bordered(40, 4), 40, 40)
    expect(insets).not.toBeNull()
    expect(insets!.top).toBeCloseTo(0.1, 5)
    expect(insets!.bottom).toBeCloseTo(0.1, 5)
    expect(insets!.left).toBeCloseTo(0.1, 5)
    expect(insets!.right).toBeCloseTo(0.1, 5)
  })

  it('黑底留白同样能识别', () => {
    const size = 40
    const data = makeImage(size, size, (x, y) =>
      x < 4 || y < 4 || x >= size - 4 || y >= size - 4 ? BLACK : WHITE
    )
    const insets = computeCropInsets(data, size, size)
    expect(insets!.top).toBeCloseTo(0.1, 5)
  })

  it('只有左右有留白时上下不裁', () => {
    const size = 40
    const data = makeImage(size, size, (x) => (x < 6 || x >= size - 6 ? WHITE : BLACK))
    const insets = computeCropInsets(data, size, size)
    expect(insets!.top).toBe(0)
    expect(insets!.bottom).toBe(0)
    expect(insets!.left).toBeCloseTo(0.15, 5)
    expect(insets!.right).toBeCloseTo(0.15, 5)
  })

  it('留白超过 25% 时按上限截断，避免吃掉内容', () => {
    const insets = computeCropInsets(bordered(40, 16), 40, 40)
    // 四边同时顶到上限会被当作空白页放弃裁剪
    expect(insets).toBeNull()
  })

  it('四角颜色不一致时放弃裁剪', () => {
    const size = 40
    const data = makeImage(size, size, (x, y) => (x + y < size ? WHITE : BLACK))
    expect(computeCropInsets(data, size, size)).toBeNull()
  })

  it('没有留白时返回 null', () => {
    const data = makeImage(40, 40, (x, y) => [(x * 6) % 255, (y * 6) % 255, 128])
    expect(computeCropInsets(data, 40, 40)).toBeNull()
  })

  it('整页纯色不裁', () => {
    const data = makeImage(40, 40, () => WHITE)
    expect(computeCropInsets(data, 40, 40)).toBeNull()
  })

  it('四边加起来不到 1% 的留白当作噪点忽略', () => {
    // 1px / 500px = 0.2% 每边，总计 0.8%
    expect(computeCropInsets(bordered(500, 1), 500, 500)).toBeNull()
  })

  it('尺寸过小或数据不完整时返回 null', () => {
    expect(computeCropInsets(new Uint8ClampedArray(16), 2, 2)).toBeNull()
    expect(computeCropInsets(new Uint8ClampedArray(16), 40, 40)).toBeNull()
  })

  it('容差内的轻微噪点仍算留白', () => {
    const size = 40
    const border = 4
    const data = makeImage(size, size, (x, y) => {
      if (x < border || y < border || x >= size - border || y >= size - border) {
        return [250, 252, 248] // 接近纯白，但不完全相等
      }
      return BLACK
    })
    const insets = computeCropInsets(data, size, size)
    expect(insets!.top).toBeCloseTo(0.1, 5)
  })
})

describe('hasCrop', () => {
  it('区分「不需要裁」与「有裁剪」', () => {
    expect(hasCrop(null)).toBe(false)
    expect(hasCrop(undefined)).toBe(false)
    expect(hasCrop({ top: 0, right: 0, bottom: 0, left: 0 })).toBe(false)
    expect(hasCrop({ top: 0.1, right: 0, bottom: 0, left: 0 })).toBe(true)
  })
})
