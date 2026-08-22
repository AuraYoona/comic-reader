/**
 * 自动裁白边：从缩小后的采样图里算出四边该裁掉的比例（纯函数，可单独单元测试）。
 *
 * 扫描版漫画常带一圈纯色留白，双页对齐和「适应宽度」都会被它拖累。
 * 这里只做最稳妥的判断：以四角颜色作为背景色，从各边向内推进，
 * 只要整行/整列都接近背景色就继续裁，遇到内容立刻停。
 */

export interface CropInsets {
  /** 0–1 之间的比例 */
  top: number
  right: number
  bottom: number
  left: number
}

export const NO_CROP: CropInsets = { top: 0, right: 0, bottom: 0, left: 0 }

/** 单通道容差：低于它就算「和背景一样」 */
const TOLERANCE = 18
/** 四角颜色差异超过它就认为没有统一背景，放弃裁剪 */
const CORNER_TOLERANCE = 24
/** 每边最多裁掉的比例，防止把内容吃掉 */
const MAX_INSET = 0.25
/** 小于这个比例的裁剪没有意义，直接当作不需要裁 */
const MIN_MEANINGFUL = 0.01

type Rgb = [number, number, number]

function pixelAt(data: Uint8ClampedArray, width: number, x: number, y: number): Rgb {
  const i = (y * width + x) * 4
  return [data[i], data[i + 1], data[i + 2]]
}

function diff(a: Rgb, b: Rgb): number {
  return Math.max(Math.abs(a[0] - b[0]), Math.abs(a[1] - b[1]), Math.abs(a[2] - b[2]))
}

/** 四角平均色；四角互相差太多则返回 null（例如跨页拼图、带花边的扫图） */
function backgroundColor(data: Uint8ClampedArray, width: number, height: number): Rgb | null {
  const corners: Rgb[] = [
    pixelAt(data, width, 0, 0),
    pixelAt(data, width, width - 1, 0),
    pixelAt(data, width, 0, height - 1),
    pixelAt(data, width, width - 1, height - 1)
  ]
  for (let i = 1; i < corners.length; i++) {
    if (diff(corners[0], corners[i]) > CORNER_TOLERANCE) return null
  }
  return [
    Math.round(corners.reduce((s, c) => s + c[0], 0) / 4),
    Math.round(corners.reduce((s, c) => s + c[1], 0) / 4),
    Math.round(corners.reduce((s, c) => s + c[2], 0) / 4)
  ]
}

function rowIsBackground(
  data: Uint8ClampedArray,
  width: number,
  y: number,
  bg: Rgb,
  fromX: number,
  toX: number
): boolean {
  for (let x = fromX; x <= toX; x++) {
    if (diff(pixelAt(data, width, x, y), bg) > TOLERANCE) return false
  }
  return true
}

function colIsBackground(
  data: Uint8ClampedArray,
  width: number,
  x: number,
  bg: Rgb,
  fromY: number,
  toY: number
): boolean {
  for (let y = fromY; y <= toY; y++) {
    if (diff(pixelAt(data, width, x, y), bg) > TOLERANCE) return false
  }
  return true
}

/**
 * 从 RGBA 采样数据算出裁剪比例。
 * 返回 null 表示不需要裁（没有统一背景、或留白少到没有意义）。
 */
export function computeCropInsets(
  data: Uint8ClampedArray,
  width: number,
  height: number
): CropInsets | null {
  if (width < 4 || height < 4 || data.length < width * height * 4) return null
  const bg = backgroundColor(data, width, height)
  if (!bg) return null

  const maxY = Math.floor(height * MAX_INSET)
  const maxX = Math.floor(width * MAX_INSET)

  let top = 0
  while (top < maxY && rowIsBackground(data, width, top, bg, 0, width - 1)) top++
  let bottom = 0
  while (bottom < maxY && rowIsBackground(data, width, height - 1 - bottom, bg, 0, width - 1)) {
    bottom++
  }
  // 左右扫描时跳过已判定为留白的上下部分，避免被它们干扰
  const innerTop = top
  const innerBottom = height - 1 - bottom
  if (innerTop >= innerBottom) return null

  let left = 0
  while (left < maxX && colIsBackground(data, width, left, bg, innerTop, innerBottom)) left++
  let right = 0
  while (
    right < maxX &&
    colIsBackground(data, width, width - 1 - right, bg, innerTop, innerBottom)
  ) {
    right++
  }

  const insets: CropInsets = {
    top: top / height,
    bottom: bottom / height,
    left: left / width,
    right: right / width
  }
  // 四边都顶到上限：多半是整页空白或纯色页，裁了没有意义，保持原样更安全
  if (top >= maxY && bottom >= maxY && left >= maxX && right >= maxX) return null
  const total = insets.top + insets.bottom + insets.left + insets.right
  if (total < MIN_MEANINGFUL) return null
  // 兜底：万一整张图都是背景色，不要裁成 0 尺寸
  if (insets.top + insets.bottom >= 1 || insets.left + insets.right >= 1) return null
  return insets
}

export function hasCrop(insets: CropInsets | null | undefined): insets is CropInsets {
  return !!insets && insets.top + insets.right + insets.bottom + insets.left > 0
}
