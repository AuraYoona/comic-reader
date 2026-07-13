/** comic:// 协议 URL 构造 */

export function pageUrl(comicId: string, index: number): string {
  return `comic://page/${comicId}/${index}`
}

/**
 * 封面 URL 用 coverFile 文件名做版本号：
 * 重新扫描会生成新文件名，URL 变化自动绕过浏览器缓存。
 */
export function coverUrl(comicId: string, coverFile: string | null): string {
  return `comic://cover/${comicId}?v=${encodeURIComponent(coverFile ?? '0')}`
}
