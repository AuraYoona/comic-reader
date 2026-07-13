/**
 * 页面预取缓存（LRU）。
 *
 * 只调用 img.decode() 把相邻页提前解码进 Chromium 的图像缓存，
 * 翻页时 <img> 命中缓存即时显示，不再有解码卡顿。
 * 持有 HTMLImageElement 引用防止预取被 GC 中断；超出容量按最旧淘汰，
 * 淘汰时清空 src 以中断仍在进行的请求。
 */

const MAX_ENTRIES = 32

const cache = new Map<string, HTMLImageElement>()

export function prefetchImage(url: string): void {
  const hit = cache.get(url)
  if (hit) {
    // 触摸一下保持 LRU 顺序
    cache.delete(url)
    cache.set(url, hit)
    return
  }
  const img = new Image()
  img.decoding = 'async'
  img.src = url
  // decode 失败（损坏图/404）无所谓，展示错误交给 PageImage
  void img.decode?.().catch(() => {})
  cache.set(url, img)
  while (cache.size > MAX_ENTRIES) {
    const oldest = cache.keys().next().value
    if (oldest === undefined) break
    const evicted = cache.get(oldest)
    cache.delete(oldest)
    if (evicted) evicted.src = ''
  }
}

/** 关闭阅读器时释放全部预取 */
export function clearPageCache(): void {
  for (const img of cache.values()) img.src = ''
  cache.clear()
}
