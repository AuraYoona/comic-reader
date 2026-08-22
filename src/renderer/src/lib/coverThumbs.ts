import type { Comic } from '@shared/types'
import { coverNeedsThumbnail } from '@shared/covers'
import { coverUrl } from '@/utils/comicUrl'
import { drawScaled, loadBitmap } from './bitmap'

/**
 * 封面二次压缩。
 *
 * 主进程的 nativeImage 解不了 WebP / AVIF / GIF，这些格式的首页会被原样存成封面。
 * 一张原图动辄几 MB，书架滚动时几百张一起进图像缓存，内存会很难看。
 * 渲染进程这边什么格式都能解，就在这里用 canvas 压成 480px 的 JPEG 回传主进程替换掉。
 *
 * 只在书架空闲时低速进行，失败的不重试（下次启动会再排一次）。
 */

const COVER_WIDTH = 480
const JPEG_QUALITY = 0.82
/** 同时最多压两张，别和书架首屏的封面加载抢解码资源 */
const MAX_CONCURRENT = 2

const queue: Comic[] = []
/** 本次会话已排过队的 id，避免重复处理 */
const attempted = new Set<string>()
let running = 0
let onUpdated: ((comic: Comic) => void) | null = null

async function reencode(comic: Comic): Promise<Uint8Array | null> {
  const bitmap = await loadBitmap(coverUrl(comic.id, comic.coverFile))
  if (!bitmap) return null
  try {
    const drawn = drawScaled(bitmap, COVER_WIDTH, Number.MAX_SAFE_INTEGER)
    if (!drawn) return null
    const blob = await drawn.canvas.convertToBlob({ type: 'image/jpeg', quality: JPEG_QUALITY })
    return new Uint8Array(await blob.arrayBuffer())
  } catch {
    return null
  } finally {
    bitmap.close()
  }
}

function pump(): void {
  while (running < MAX_CONCURRENT && queue.length > 0) {
    const comic = queue.shift()
    if (!comic) break
    running++
    void (async () => {
      try {
        const jpeg = await reencode(comic)
        if (jpeg) {
          const updated = await window.api.saveCoverThumbnail(comic.id, jpeg)
          if (updated) onUpdated?.(updated)
        }
      } catch {
        /* 封面压缩纯属优化，失败了保持原样即可 */
      } finally {
        running--
        pump()
      }
    })()
  }
}

/** 把还是原图直存的封面排进压缩队列 */
export function enqueueCoverThumbnails(comics: Comic[], onDone: (comic: Comic) => void): void {
  onUpdated = onDone
  for (const comic of comics) {
    if (!coverNeedsThumbnail(comic.coverFile) || attempted.has(comic.id)) continue
    attempted.add(comic.id)
    queue.push(comic)
  }
  // 让首屏封面先画出来，压缩排在空闲时段
  if (queue.length > 0) requestIdleCallback(() => pump(), { timeout: 3000 })
}

/** 重新扫描后封面换了新文件，允许再排一次 */
export function forgetCoverAttempt(comicId: string): void {
  attempted.delete(comicId)
}
