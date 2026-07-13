/** 展示用的格式化工具 */

export function relativeTime(ts: number | null): string {
  if (!ts) return '未读'
  const diff = Date.now() - ts
  const minute = 60_000
  const hour = 60 * minute
  const day = 24 * hour
  if (diff < minute) return '刚刚'
  if (diff < hour) return `${Math.floor(diff / minute)} 分钟前`
  if (diff < day) return `${Math.floor(diff / hour)} 小时前`
  if (diff < 30 * day) return `${Math.floor(diff / day)} 天前`
  const d = new Date(ts)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(
    d.getDate()
  ).padStart(2, '0')}`
}

/** 阅读百分比（0-100 的整数）。未读返回 0。 */
export function readPercent(lastReadAt: number | null, lastReadPage: number, pageCount: number): number {
  if (!lastReadAt || pageCount <= 0) return 0
  return Math.min(100, Math.round(((lastReadPage + 1) / pageCount) * 100))
}

export function basename(p: string): string {
  return p.split(/[\\/]/).pop() ?? p
}
