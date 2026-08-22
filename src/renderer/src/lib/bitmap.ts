/**
 * 把 comic:// 的图片取成位图。
 *
 * 必须走 fetch → blob → createImageBitmap 这条路：comic:// 与页面不同源，
 * 直接用 <img> 画进 canvas 会污染画布，后续 getImageData / convertToBlob 都会抛错。
 * 主进程在 comic:// 的响应里带了 Access-Control-Allow-Origin，fetch 才能拿到字节。
 */
export async function loadBitmap(url: string): Promise<ImageBitmap | null> {
  try {
    const res = await fetch(url)
    if (!res.ok) return null
    const blob = await res.blob()
    return await createImageBitmap(blob)
  } catch {
    return null
  }
}

/** 把位图按最长边缩到 max 以内，返回 2D 上下文与实际尺寸 */
export function drawScaled(
  bitmap: ImageBitmap,
  maxWidth: number,
  maxHeight = maxWidth
): {
  canvas: OffscreenCanvas
  ctx: OffscreenCanvasRenderingContext2D
  w: number
  h: number
} | null {
  const scale = Math.min(1, maxWidth / bitmap.width, maxHeight / bitmap.height)
  const w = Math.max(1, Math.round(bitmap.width * scale))
  const h = Math.max(1, Math.round(bitmap.height * scale))
  const canvas = new OffscreenCanvas(w, h)
  const ctx = canvas.getContext('2d', { willReadFrequently: true })
  if (!ctx) return null
  ctx.drawImage(bitmap, 0, 0, w, h)
  return { canvas, ctx, w, h }
}
