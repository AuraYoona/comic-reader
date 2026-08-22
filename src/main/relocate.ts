import { promises as fsp } from 'node:fs'
import path from 'node:path'
import type { Comic } from '@shared/types'
import { isArchivePath, invalidateComic, releaseSource } from './archive'
import { logger } from './lib/logger'
import { db } from './store/db'
import { redactPath } from './utils/redact'
import { buildNameIndex, pickMatch, toIndexedEntry, type IndexedEntry } from './utils/relocate'

/** 索引深度：够覆盖「库根 / 作者 / 作品 / 卷」这种常见层级，又不会把整块盘走一遍 */
const MAX_DEPTH = 4
/** 候选项上限，防止选错目录（例如整个 D 盘）时无限扫描 */
const MAX_ENTRIES = 60_000

/** 递归收集新根目录下所有的文件夹与压缩包，作为重定位候选 */
async function indexRoot(root: string, depth: number, out: IndexedEntry[]): Promise<void> {
  if (depth > MAX_DEPTH || out.length >= MAX_ENTRIES) return
  let entries
  try {
    entries = await fsp.readdir(root, { withFileTypes: true })
  } catch {
    return // 单个子目录读不了就跳过
  }
  for (const ent of entries) {
    if (out.length >= MAX_ENTRIES) return
    if (ent.name.startsWith('.') || ent.name === '__MACOSX') continue
    const full = path.join(root, ent.name)
    if (ent.isDirectory()) {
      out.push(toIndexedEntry(full))
      await indexRoot(full, depth + 1, out)
    } else if (ent.isFile() && isArchivePath(ent.name)) {
      out.push(toIndexedEntry(full))
    }
  }
}

export interface RelocateOutcome {
  relocated: Comic[]
  unmatched: number
  scanned: number
}

/**
 * 在新根目录下按文件（夹）名重新绑定来源路径。
 *
 * 整个库从 D: 搬到 E: 之后，旧路径全部失效；重新导入会丢掉阅读进度、分类与书签，
 * 这里只改写 sourcePath，其余记录原样保留。找不到对应文件的条目保持不动。
 */
export async function relocateUnderRoot(root: string, targets: Comic[]): Promise<RelocateOutcome> {
  const entries: IndexedEntry[] = []
  await indexRoot(root, 1, entries)
  if (entries.length >= MAX_ENTRIES) {
    logger.warn('library', `重定位索引达到上限 ${MAX_ENTRIES} 项，可能遗漏更深的目录`)
  }
  const index = buildNameIndex(entries)

  const relocated: Comic[] = []
  let unmatched = 0
  for (const comic of targets) {
    const found = pickMatch(comic.sourcePath, index)
    if (!found || found === comic.sourcePath) {
      unmatched++
      continue
    }
    // 旧路径可能还占着压缩包句柄与页面列表缓存，一并作废
    releaseSource(comic.sourcePath)
    invalidateComic(comic.id)
    const updated = db.setSourcePath(comic.id, found)
    if (updated) relocated.push(updated)
    else unmatched++
  }

  logger.info(
    'library',
    `来源重定位：根目录 ${redactPath(root)}，候选 ${entries.length} 项，改绑 ${relocated.length} 本，未匹配 ${unmatched} 本`
  )
  return { relocated, unmatched, scanned: entries.length }
}
