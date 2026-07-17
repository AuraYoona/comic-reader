import { promises as fsp } from 'node:fs'
import { randomUUID } from 'node:crypto'
import path from 'node:path'
import type { Comic, ImportResult, SourceType } from '@shared/types'
import type { ImportProgress } from '@shared/api'
import { SourceError, readEntry, scanSource } from './archive'
import { logger } from './lib/logger'
import { db } from './store/db'
import { normalizeForCompare } from './utils/images'
import { makeCoverThumbnail } from './thumbnail'

const ARCHIVE_RE = /\.(zip|cbz)$/i

function failed(p: string, reason: string): ImportResult {
  return { path: p, status: 'failed', reason }
}

/** 生成封面文件并返回文件名；任何一步失败都返回 null（封面缺失不阻塞导入） */
async function generateCover(
  fileBase: string,
  sourceType: SourceType,
  sourcePath: string,
  firstPage: string
): Promise<string | null> {
  try {
    const { data } = await readEntry(sourceType, sourcePath, firstPage)
    const thumb = makeCoverThumbnail(data)
    const ext = thumb ? '.jpg' : path.extname(firstPage).toLowerCase()
    const fileName = `${fileBase}${ext}`
    await fsp.mkdir(db.coversDir(), { recursive: true })
    await fsp.writeFile(path.join(db.coversDir(), fileName), thumb ?? data)
    return fileName
  } catch (err) {
    logger.warn('importer', `生成封面失败：${sourcePath}`, err)
    return null
  }
}

/**
 * 重新生成封面（“重新扫描”功能用）。
 * 文件名带时间戳：封面 URL 由文件名派生，重扫后书架立刻显示新图而不受浏览器缓存影响。
 */
export async function regenerateCover(comic: Comic, firstPage: string): Promise<string | null> {
  const fileName = await generateCover(
    `${comic.id}-${Date.now()}`,
    comic.sourceType,
    comic.sourcePath,
    firstPage
  )
  if (fileName && comic.coverFile && comic.coverFile !== fileName) {
    await fsp.rm(path.join(db.coversDir(), comic.coverFile), { force: true }).catch(() => {})
  }
  return fileName
}

async function importOne(rawPath: string, seenInBatch: Set<string>): Promise<ImportResult> {
  const sourcePath = path.resolve(rawPath)
  try {
    const st = await fsp.stat(sourcePath).catch(() => null)
    if (!st) return failed(sourcePath, '路径不存在')

    let sourceType: SourceType
    if (st.isDirectory()) sourceType = 'folder'
    else if (st.isFile() && ARCHIVE_RE.test(sourcePath)) sourceType = 'archive'
    else return failed(sourcePath, '不支持的文件类型（支持文件夹、ZIP、CBZ）')

    const norm = normalizeForCompare(sourcePath)
    if (seenInBatch.has(norm)) return { path: sourcePath, status: 'skipped', reason: '重复选择' }
    seenInBatch.add(norm)

    const existing = db.listComics().find((c) => normalizeForCompare(c.sourcePath) === norm)
    if (existing) {
      return { path: sourcePath, status: 'skipped', reason: '已在书架中', comic: existing }
    }

    const pages = await scanSource(sourceType, sourcePath)
    if (pages.length === 0) {
      return failed(
        sourcePath,
        sourceType === 'folder' ? '文件夹中没有找到图片' : '压缩包中没有找到图片'
      )
    }

    const id = randomUUID()
    const base = path.basename(sourcePath)
    const title = sourceType === 'archive' ? base.replace(ARCHIVE_RE, '') : base
    const coverFile = await generateCover(id, sourceType, sourcePath, pages[0])

    const comic: Comic = {
      id,
      title,
      sourceType,
      sourcePath,
      pageCount: pages.length,
      coverFile,
      addedAt: Date.now(),
      lastReadAt: null,
      lastReadPage: 0,
      reader: {},
      // 新导入的漫画不属于任何分类
      categoryIds: []
    }
    db.upsertComic(comic)
    return { path: sourcePath, status: 'imported', comic }
  } catch (err) {
    const msg =
      err instanceof SourceError
        ? err.message
        : `导入失败：${err instanceof Error ? err.message : String(err)}`
    return failed(sourcePath, msg)
  }
}

/** 批量导入。逐项处理并回调进度，单项失败不影响其余项。 */
export async function importPaths(
  paths: string[],
  onProgress?: (p: ImportProgress) => void
): Promise<ImportResult[]> {
  const results: ImportResult[] = []
  const seenInBatch = new Set<string>()
  for (let i = 0; i < paths.length; i++) {
    onProgress?.({ current: i + 1, total: paths.length, path: paths[i] })
    results.push(await importOne(paths[i], seenInBatch))
  }
  const imported = results.filter((r) => r.status === 'imported').length
  const failed = results.filter((r) => r.status === 'failed').length
  logger.info('importer', `导入完成：成功 ${imported}，跳过 ${results.length - imported - failed}，失败 ${failed}`)
  return results
}

/**
 * 把“漫画库根目录”展开成待导入项：每个子文件夹或压缩包算一本。
 * 返回 null 表示根目录本身读不了。
 */
export async function expandBatchRoot(root: string): Promise<string[] | null> {
  try {
    const entries = await fsp.readdir(root, { withFileTypes: true })
    return entries
      .filter((e) => !e.name.startsWith('.'))
      .filter((e) => e.isDirectory() || (e.isFile() && ARCHIVE_RE.test(e.name)))
      .map((e) => path.join(root, e.name))
  } catch (err) {
    logger.warn('importer', `批量导入：无法读取根目录 ${root}`, err)
    return null
  }
}
