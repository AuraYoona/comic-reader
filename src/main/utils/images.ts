import path from 'node:path'

/** 支持的图片扩展名（Chromium 能直接解码的格式） */
export const IMAGE_EXTS = new Set([
  '.jpg',
  '.jpeg',
  '.jfif',
  '.png',
  '.webp',
  '.gif',
  '.avif',
  '.bmp'
])

const MIME_BY_EXT: Record<string, string> = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.jfif': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
  '.avif': 'image/avif',
  '.bmp': 'image/bmp'
}

/** 是否为受支持的图片文件（按扩展名判断，忽略隐藏文件） */
export function isImagePath(p: string): boolean {
  const base = path.basename(p)
  // 只跳过隐藏文件（.DS_Store、._resource-fork 等）；`_001.jpg` 这类正常命名要保留
  if (base.startsWith('.')) return false
  return IMAGE_EXTS.has(path.extname(base).toLowerCase())
}

/** 压缩包条目路径是否应被忽略（隐藏目录、系统目录） */
export function isJunkEntry(entryName: string): boolean {
  return entryName
    .split(/[\\/]/)
    .some((seg) => seg.startsWith('.') || seg === '__MACOSX' || seg.startsWith('__MACOSX'))
}

export function mimeFor(p: string): string {
  return MIME_BY_EXT[path.extname(p).toLowerCase()] ?? 'application/octet-stream'
}

/** 归一化路径用于去重比较（Windows 不区分大小写） */
export function normalizeForCompare(p: string): string {
  const resolved = path.resolve(p)
  return process.platform === 'win32' ? resolved.toLowerCase() : resolved
}
