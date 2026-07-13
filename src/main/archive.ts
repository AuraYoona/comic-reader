import { promises as fsp } from 'node:fs'
import path from 'node:path'
import StreamZip from 'node-stream-zip'
import type { Comic, SourceType } from '@shared/types'
import { isImagePath, isJunkEntry, mimeFor } from './utils/images'
import { naturalCompare } from './utils/naturalSort'

/** 来源相关的可预期错误（路径丢失、压缩包损坏等），消息可直接展示给用户 */
export class SourceError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'SourceError'
  }
}

/** 把文件系统 errno 翻译成用户能看懂的话 */
function ioError(err: unknown, fallback: string): SourceError {
  const code = (err as NodeJS.ErrnoException | null)?.code
  switch (code) {
    case 'ENOENT':
      return new SourceError('文件或文件夹不存在，可能已被移动或删除')
    case 'EACCES':
    case 'EPERM':
      return new SourceError('没有读取权限，请检查文件（夹）的访问权限')
    case 'EBUSY':
      return new SourceError('文件正被其他程序占用，请稍后重试')
    case 'EMFILE':
    case 'ENFILE':
      return new SourceError('系统打开的文件过多，请稍后重试')
    default:
      return new SourceError(fallback)
  }
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

type ZipHandle = InstanceType<typeof StreamZip.async>

// ---------------------------------------------------------------------------
// ZIP 句柄缓存：阅读时按页读取同一个压缩包，避免每页都重新打开文件。
// 空闲 60s 或超过上限后关闭。
// ---------------------------------------------------------------------------

const ZIP_IDLE_MS = 60_000
const ZIP_MAX_OPEN = 4

interface CachedZip {
  zip: ZipHandle
  timer: NodeJS.Timeout
}

const zipCache = new Map<string, CachedZip>()

function evictZip(file: string): void {
  const hit = zipCache.get(file)
  if (!hit) return
  clearTimeout(hit.timer)
  zipCache.delete(file)
  hit.zip.close().catch(() => {})
}

async function getZip(file: string): Promise<ZipHandle> {
  const hit = zipCache.get(file)
  if (hit) {
    clearTimeout(hit.timer)
    hit.timer = setTimeout(() => evictZip(file), ZIP_IDLE_MS)
    return hit.zip
  }
  // 超过上限先关掉最旧的（Map 保持插入顺序）
  while (zipCache.size >= ZIP_MAX_OPEN) {
    const oldest = zipCache.keys().next().value
    if (oldest === undefined) break
    evictZip(oldest)
  }
  let zip: ZipHandle
  try {
    zip = new StreamZip.async({ file })
    await zip.entriesCount // 触发中央目录解析，尽早暴露损坏的包
  } catch {
    throw new SourceError('无法读取压缩包，文件可能已损坏或不是有效的 ZIP/CBZ')
  }
  const timer = setTimeout(() => evictZip(file), ZIP_IDLE_MS)
  zipCache.set(file, { zip, timer })
  return zip
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

/** 扫描来源，返回自然排序后的页面条目列表（folder 为相对路径，archive 为 zip 条目名） */
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
          : `压缩包不存在，可能已被移动或删除：${sourcePath}`
      )
    }
    throw ioError(err, `无法访问：${sourcePath}`)
  }

  if (sourceType === 'folder') {
    if (!st.isDirectory()) throw new SourceError('该路径不是文件夹')
    const out: string[] = []
    await walkFolderImages(sourcePath, '', out)
    return out.sort(naturalCompare)
  }

  if (!st.isFile()) throw new SourceError('该路径不是文件')
  const zip = await getZip(sourcePath)
  const entries = await zip.entries()
  return Object.values(entries)
    .filter((e) => !e.isDirectory && !isJunkEntry(e.name) && isImagePath(e.name))
    .map((e) => e.name)
    .sort(naturalCompare)
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
  try {
    const zip = await getZip(sourcePath)
    const data = await zip.entryData(entry)
    return { data, mime: mimeFor(entry) }
  } catch (err) {
    if (err instanceof SourceError) throw err
    // 句柄可能因文件被替换而失效：丢掉缓存重试一次
    evictZip(sourcePath)
    try {
      const zip = await getZip(sourcePath)
      const data = await zip.entryData(entry)
      return { data, mime: mimeFor(entry) }
    } catch {
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
  for (const file of [...zipCache.keys()]) evictZip(file)
}
