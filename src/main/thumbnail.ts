import { nativeImage } from 'electron'

const COVER_WIDTH = 480
const COVER_JPEG_QUALITY = 82

/**
 * 用 Electron 自带的 nativeImage 生成封面缩略图（JPEG）。
 * nativeImage 只能解码 PNG/JPEG；WebP/GIF 会返回空图，
 * 此时返回 null，由调用方直接把原图存为封面。
 */
export function makeCoverThumbnail(source: Buffer): Buffer | null {
  try {
    let img = nativeImage.createFromBuffer(source)
    if (img.isEmpty()) return null
    const { width } = img.getSize()
    if (width > COVER_WIDTH) {
      img = img.resize({ width: COVER_WIDTH, quality: 'good' })
    }
    const jpeg = img.toJPEG(COVER_JPEG_QUALITY)
    return jpeg.length > 0 ? jpeg : null
  } catch {
    return null
  }
}
