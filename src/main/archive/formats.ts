import path from 'node:path'
import { ARCHIVE_EXTS } from '@shared/archives'

export { ARCHIVE_EXTS, isArchivePath, stripArchiveExt } from '@shared/archives'

/** 支持的文件来源格式 */
export type ArchiveFormat = 'zip' | 'rar' | 'pdf'

const FORMAT_BY_EXT: Record<string, ArchiveFormat> = {
  '.zip': 'zip',
  '.cbz': 'zip',
  '.rar': 'rar',
  '.cbr': 'rar',
  '.pdf': 'pdf'
}

/** 系统对话框的过滤器用（不含点） */
export const ARCHIVE_FILTER_EXTS: readonly string[] = ARCHIVE_EXTS.map((e) => e.slice(1))

/** 按扩展名判断文件来源格式，不受支持返回 null */
export function archiveFormat(p: string): ArchiveFormat | null {
  return FORMAT_BY_EXT[path.extname(p).toLowerCase()] ?? null
}
