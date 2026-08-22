import { nativeImage } from 'electron'

export { COVER_THUMB_EXT, isGeneratedCover } from '@shared/covers'

const COVER_WIDTH = 480
const COVER_JPEG_QUALITY = 82

/** 跳页缩略图条用的小图 */
const PAGE_THUMB_WIDTH = 180
const PAGE_THUMB_QUALITY = 70

/**
 * 用 Electron 自带的 nativeImage 缩图（输出 JPEG）。
 * nativeImage 只能解码 PNG/JPEG；WebP/GIF/AVIF 会返回空图，此时返回 null，
 * 由调用方决定回退方案（封面直存原图，之后由渲染进程用 canvas 重压）。
 */
function makeThumbnail(source: Buffer, width: number, quality: number): Buffer | null {
  try {
    let img = nativeImage.createFromBuffer(source)
    if (img.isEmpty()) return null
    const size = img.getSize()
    if (size.width > width) {
      img = img.resize({ width, quality: 'good' })
    }
    const jpeg = img.toJPEG(quality)
    return jpeg.length > 0 ? jpeg : null
  } catch {
    return null
  }
}

export function makeCoverThumbnail(source: Buffer): Buffer | null {
  return makeThumbnail(source, COVER_WIDTH, COVER_JPEG_QUALITY)
}

export function makePageThumbnail(source: Buffer): Buffer | null {
  return makeThumbnail(source, PAGE_THUMB_WIDTH, PAGE_THUMB_QUALITY)
}

/** JPEG 魔数校验：渲染进程回传的封面字节必须先验明正身再落盘 */
export function isJpegBuffer(data: Buffer): boolean {
  return data.length > 3 && data[0] === 0xff && data[1] === 0xd8 && data[2] === 0xff
}
