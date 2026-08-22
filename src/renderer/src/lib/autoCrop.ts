import { computeCropInsets, type CropInsets } from '@shared/crop'
import { drawScaled, loadBitmap } from './bitmap'

/**
 * 自动裁白边的运行时部分：取图 → 缩到小采样图 → 交给纯函数算比例。
 *
 * 采样图很小（最长边 96px），一张的代价约等于解一次缩略图；结果按 URL 缓存，
 * 同一页翻来翻去只算一次。
 */

const SAMPLE_MAX = 96
const MAX_CACHE = 400

/** undefined = 没算过；null = 算过但不需要裁 */
const cache = new Map<string, CropInsets | null>()
const inflight = new Map<string, Promise<CropInsets | null>>()

export function getCachedCrop(url: string): CropInsets | null | undefined {
  return cache.get(url)
}

function remember(url: string, value: CropInsets | null): CropInsets | null {
  cache.set(url, value)
  while (cache.size > MAX_CACHE) {
    const oldest = cache.keys().next().value
    if (oldest === undefined) break
    cache.delete(oldest)
  }
  return value
}

export function measureCrop(url: string): Promise<CropInsets | null> {
  const cached = cache.get(url)
  if (cached !== undefined) return Promise.resolve(cached)
  const running = inflight.get(url)
  if (running) return running

  const task = (async (): Promise<CropInsets | null> => {
    const bitmap = await loadBitmap(url)
    if (!bitmap) return remember(url, null)
    try {
      const drawn = drawScaled(bitmap, SAMPLE_MAX)
      if (!drawn) return remember(url, null)
      const { data } = drawn.ctx.getImageData(0, 0, drawn.w, drawn.h)
      return remember(url, computeCropInsets(data, drawn.w, drawn.h))
    } catch {
      return remember(url, null)
    } finally {
      bitmap.close()
      inflight.delete(url)
    }
  })()

  inflight.set(url, task)
  return task
}

/** 关闭阅读器 / 重新扫描后清空 */
export function clearCropCache(): void {
  cache.clear()
  inflight.clear()
}
