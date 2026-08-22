import { promises as fsp } from 'node:fs'
import path from 'node:path'
import type { Comic, SourceType } from '@shared/types'
import { isImagePath, isJunkEntry, mimeFor } from '../utils/images'
import { naturalCompare } from '../utils/naturalSort'
import { SourceError, ioError } from './errors'
import { archiveFormat } from './formats'
import { rarReader } from './rar'
import type { ArchiveReader } from './reader'
import { zipReader } from './zip'

export { SourceError } from './errors'
export {
  ARCHIVE_EXTS,
  ARCHIVE_FILTER_EXTS,
  archiveFormat,
  isArchivePath,
  stripArchiveExt
} from './formats'

const READERS: ArchiveReader[] = [zipReader, rarReader]

/** 按扩展名挑选压缩包适配器 */
function readerFor(sourcePath: string): ArchiveReader {
  const format = archiveFormat(sourcePath)
  if (format === 'zip') return zipReader
  if (format === 'rar') return rarReader
  throw new SourceError('不支持的压缩包格式（支持 ZIP、CBZ、RAR、CBR）')
}

/** 来源是否仍然可访问（书架“来源丢失”校验用） */
export async function sourceExists(sourcePath: string): Promise<boolean> {
  try {
    await fsp.access(sourcePath)
    return true
  } catch {
    return false
  }
}

// ---------------------------------------------------------------------------
// 目录/压缩包扫描
// ---------------------------------------------------------------------------

async function walkFolderImages(root: string, rel: string, out: string[]): Promise<void> {
  let entries
  try {
    entries = await fsp.readdir(path.join(root, rel), { withFileTypes: true })
  } catch (err) {
    if (rel === '') throw ioError(err, '无法读取文件夹')
    return // 子目录读不了就跳过，不让整本失败
  }
  for (const ent of entries) {
    if (ent.name.startsWith('.') || ent.name === '__MACOSX') continue
    const relPath = rel ? `${rel}/${ent.name}` : ent.name
    if (ent.isDirectory()) {
      await walkFolderImages(root, relPath, out)
    } else if (ent.isFile() && isImagePath(ent.name)) {
      out.push(relPath)
    }
  }
}

/** 扫描来源，返回自然排序后的页面条目列表（folder 为相对路径，archive 为压缩包条目名） */
export async function scanSource(sourceType: SourceType, sourcePath: string): Promise<string[]> {
  let st
  try {
    st = await fsp.stat(sourcePath)
  } catch (err) {
    const code = (err as NodeJS.ErrnoException | null)?.code
    if (code === 'ENOENT') {
      throw new SourceError(
        sourceType === 'folder'
          ? `文件夹不存在，可能已被移动或删除：${sourcePath}`
          : `压缩包不存在，可能已被移动或删除：${sourcePath}`,
        sourcePath
      )
    }
    throw ioError(err, `无法访问：${sourcePath}`, sourcePath)
  }

  if (sourceType === 'folder') {
    if (!st.isDirectory()) throw new SourceError('该路径不是文件夹')
    const out: string[] = []
    await walkFolderImages(sourcePath, '', out)
    return out.sort(naturalCompare)
  }

  if (!st.isFile()) throw new SourceError('该路径不是文件')
  const entries = await readerFor(sourcePath).list(sourcePath)
  return entries
    .filter((e) => !e.isDirectory && !isJunkEntry(e.name) && isImagePath(e.name))
    .map((e) => e.name)
    .sort(naturalCompare)
}

/** 释放某个来源占用的压缩包句柄 */
export function releaseSource(sourcePath: string): void {
  if (archiveFormat(sourcePath)) readerFor(sourcePath).release(sourcePath)
}

/** 读取来源中的单个条目字节 */
export async function readEntry(
  sourceType: SourceType,
  sourcePath: string,
  entry: string
): Promise<{ data: Buffer; mime: string }> {
  if (sourceType === 'folder') {
    try {
      const data = await fsp.readFile(path.join(sourcePath, entry))
      return { data, mime: mimeFor(entry) }
    } catch (err) {
      throw ioError(err, '图片读取失败')
    }
  }

  const reader = readerFor(sourcePath)
  try {
    return { data: await reader.read(sourcePath, entry), mime: mimeFor(entry) }
  } catch (err) {
    if (err instanceof SourceError) throw err
    // 句柄可能因文件被替换而失效：丢掉缓存重试一次
    reader.release(sourcePath)
    try {
      return { data: await reader.read(sourcePath, entry), mime: mimeFor(entry) }
    } catch (retryErr) {
      if (retryErr instanceof SourceError) throw retryErr
      throw new SourceError('读取压缩包内图片失败，文件可能已损坏')
    }
  }
}

// ---------------------------------------------------------------------------
// 每本漫画的页面列表缓存（阅读会话内复用，打开漫画时强制刷新）
// ---------------------------------------------------------------------------

const pageListCache = new Map<string, string[]>()

export function invalidateComic(comicId: string): void {
  pageListCache.delete(comicId)
}

export async function getPageList(comic: Comic): Promise<string[]> {
  const cached = pageListCache.get(comic.id)
  if (cached) return cached
  const pages = await scanSource(comic.sourceType, comic.sourcePath)
  pageListCache.set(comic.id, pages)
  return pages
}

/** 按页码读取图片（comic:// 协议的数据来源） */
export async function readPage(
  comic: Comic,
  index: number
): Promise<{ data: Buffer; mime: string }> {
  const pages = await getPageList(comic)
  if (!Number.isInteger(index) || index < 0 || index >= pages.length) {
    throw new SourceError(`页码超出范围：${index + 1} / ${pages.length}`)
  }
  return readEntry(comic.sourceType, comic.sourcePath, pages[index])
}

/** 退出前清理打开的压缩包句柄 */
export function closeAllSources(): void {
  for (const reader of READERS) reader.releaseAll()
}
