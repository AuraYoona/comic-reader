/** 生成封面统一用 JPEG */
export const COVER_THUMB_EXT = '.jpg'

/**
 * 封面是不是我们生成的缩略图。
 *
 * 主进程的 nativeImage 只能解码 PNG/JPEG，遇到 WebP/AVIF/GIF 的首页会把原图
 * 直接当封面存下来（保留原扩展名）。扩展名因此就是「是否已压过」的标记，
 * 不需要再往数据结构里加字段。
 */
export function isGeneratedCover(coverFile: string | null): boolean {
  return !!coverFile && coverFile.toLowerCase().endsWith(COVER_THUMB_EXT)
}

/** 这张封面还是原图直存，需要渲染进程用 canvas 重压一次 */
export function coverNeedsThumbnail(coverFile: string | null): boolean {
  return !!coverFile && !isGeneratedCover(coverFile)
}
