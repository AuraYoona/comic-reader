/** 受支持的文件来源扩展名（含点，小写）。主进程按它分派读取实现，渲染进程用它还原标题。 */
export const ARCHIVE_EXTS: readonly string[] = ['.zip', '.cbz', '.rar', '.cbr', '.pdf']

/** 取扩展名（含点，小写）；没有扩展名返回空串 */
function extname(p: string): string {
  const base = p.split(/[\\/]+/).pop() ?? p
  const dot = base.lastIndexOf('.')
  return dot > 0 ? base.slice(dot).toLowerCase() : ''
}

export function isArchivePath(p: string): boolean {
  return ARCHIVE_EXTS.includes(extname(p))
}

/** 去掉压缩包扩展名，用作漫画标题 */
export function stripArchiveExt(name: string): string {
  const ext = extname(name)
  return ARCHIVE_EXTS.includes(ext) ? name.slice(0, -ext.length) : name
}
