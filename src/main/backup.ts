import { promises as fsp } from 'node:fs'
import { randomUUID } from 'node:crypto'
import path from 'node:path'
import { type BrowserWindow, dialog } from 'electron'
import type { BackupResult, Category, Comic, RestoreMode, RestoreResult } from '@shared/types'
import { logger } from './lib/logger'
import { db, normalizeLibraryData, type LibraryFile } from './store/db'
import { normalizeForCompare } from './utils/images'
import { redactPath } from './utils/redact'

const LIBRARY_FILE = 'library.json'
const COVERS_DIR = 'covers'

function stamp(): string {
  const d = new Date()
  const p = (n: number): string => String(n).padStart(2, '0')
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}`
}

/** 只取文件名，杜绝备份数据里带 ../ 之类的路径穿越 */
function safeCoverName(name: string): string | null {
  const base = path.basename(name)
  if (!base || base === '.' || base === '..' || base !== name) return null
  return base
}

async function copyCover(fromDir: string, toDir: string, fileName: string): Promise<boolean> {
  try {
    await fsp.copyFile(path.join(fromDir, fileName), path.join(toDir, fileName))
    return true
  } catch {
    return false
  }
}

// ---------------------------------------------------------------------------
// 导出
// ---------------------------------------------------------------------------

/** 把书架数据与封面导出到用户选择的文件夹下的一个带时间戳的子目录 */
export async function backupLibrary(win: BrowserWindow | null): Promise<BackupResult> {
  if (!win) return { canceled: true, ok: false }
  const picked = await dialog.showOpenDialog(win, {
    title: '选择备份保存位置',
    properties: ['openDirectory', 'createDirectory'],
    buttonLabel: '备份到这里'
  })
  const parent = picked.filePaths[0]
  if (picked.canceled || !parent) return { canceled: true, ok: false }

  const dir = path.join(parent, `comic-reader-backup-${stamp()}`)
  try {
    // 退出前的数据也要落盘，保证导出的是最新状态
    db.flushSync()
    const data = db.snapshot()
    await fsp.mkdir(path.join(dir, COVERS_DIR), { recursive: true })
    // 备份文件是给人看的，这里保留缩进
    await fsp.writeFile(path.join(dir, LIBRARY_FILE), JSON.stringify(data, null, 2), 'utf-8')

    const coversFrom = db.coversDir()
    const coversTo = path.join(dir, COVERS_DIR)
    let covers = 0
    for (const comic of data.comics) {
      const name = comic.coverFile && safeCoverName(comic.coverFile)
      if (!name) continue
      if (await copyCover(coversFrom, coversTo, name)) covers++
    }

    logger.info(
      'backup',
      `导出完成：${data.comics.length} 本、${covers} 张封面 → ${redactPath(dir)}`
    )
    return { canceled: false, ok: true, path: dir, comics: data.comics.length, covers }
  } catch (err) {
    logger.error('backup', '导出失败', err)
    return {
      canceled: false,
      ok: false,
      error: `导出失败：${err instanceof Error ? err.message : String(err)}`
    }
  }
}

// ---------------------------------------------------------------------------
// 导入
// ---------------------------------------------------------------------------

async function readBackup(dir: string): Promise<LibraryFile> {
  const text = await fsp.readFile(path.join(dir, LIBRARY_FILE), 'utf-8')
  const { data } = normalizeLibraryData(JSON.parse(text))
  return data
}

/**
 * 合并：只补充书架里没有的来源，已存在的原样跳过。
 * 分类按名称对齐（同名复用本地的），漫画一律换新 id 以免与本地记录撞车。
 */
async function mergeBackup(data: LibraryFile, coversFrom: string): Promise<RestoreResult> {
  const categoryIdMap = new Map<string, string>()
  const localByName = new Map<string, Category>(db.listCategories().map((c) => [c.name, c]))
  for (const cat of data.categories) {
    const local = localByName.get(cat.name)
    if (local) {
      categoryIdMap.set(cat.id, local.id)
    } else {
      const created = db.createCategory(cat.name, cat.color)
      localByName.set(created.name, created)
      categoryIdMap.set(cat.id, created.id)
    }
  }

  const known = new Set(db.listComics().map((c) => normalizeForCompare(c.sourcePath)))
  const coversTo = db.coversDir()
  await fsp.mkdir(coversTo, { recursive: true })

  let imported = 0
  let skipped = 0
  for (const comic of data.comics) {
    const norm = normalizeForCompare(comic.sourcePath)
    if (known.has(norm)) {
      skipped++
      continue
    }
    known.add(norm)

    const id = randomUUID()
    let coverFile: string | null = null
    const name = comic.coverFile && safeCoverName(comic.coverFile)
    if (name) {
      const target = `${id}${path.extname(name).toLowerCase()}`
      try {
        await fsp.copyFile(path.join(coversFrom, name), path.join(coversTo, target))
        coverFile = target
      } catch {
        /* 封面丢了不影响记录本身，书架会显示占位图 */
      }
    }

    const restored: Comic = {
      ...comic,
      id,
      coverFile,
      categoryIds: comic.categoryIds
        .map((cid) => categoryIdMap.get(cid))
        .filter((cid): cid is string => !!cid)
    }
    db.upsertComic(restored)
    imported++
  }

  logger.info('backup', `合并导入完成：新增 ${imported} 本，跳过 ${skipped} 本`)
  return { canceled: false, ok: true, mode: 'merge', imported, skipped }
}

/** 覆盖：整库替换，替换前把当前的 library.json 另存一份 */
async function replaceWithBackup(data: LibraryFile, coversFrom: string): Promise<RestoreResult> {
  db.flushSync()
  const libraryPath = db.libraryPath()
  try {
    await fsp.copyFile(libraryPath, `${libraryPath}.pre-restore-${Date.now()}.bak`)
  } catch (err) {
    logger.warn('backup', '覆盖恢复前的自动备份失败（继续恢复）', err)
  }

  const coversTo = db.coversDir()
  await fsp.mkdir(coversTo, { recursive: true })
  const wanted = new Set<string>()
  for (const comic of data.comics) {
    const name = comic.coverFile && safeCoverName(comic.coverFile)
    if (!name) {
      comic.coverFile = null
      continue
    }
    if (await copyCover(coversFrom, coversTo, name)) wanted.add(name)
    else comic.coverFile = null
  }

  db.replaceAll(data)

  // 清掉不再被引用的旧封面，避免目录无限膨胀
  try {
    for (const file of await fsp.readdir(coversTo)) {
      if (!wanted.has(file)) await fsp.rm(path.join(coversTo, file), { force: true })
    }
  } catch (err) {
    logger.warn('backup', '清理无主封面失败', err)
  }

  logger.info('backup', `覆盖恢复完成：${data.comics.length} 本`)
  return { canceled: false, ok: true, mode: 'replace', imported: data.comics.length, skipped: 0 }
}

/** 从备份文件夹恢复数据 */
export async function restoreLibrary(
  win: BrowserWindow | null,
  mode: RestoreMode
): Promise<RestoreResult> {
  if (!win) return { canceled: true, ok: false }
  const picked = await dialog.showOpenDialog(win, {
    title: '选择备份文件夹（内含 library.json）',
    properties: ['openDirectory'],
    buttonLabel: '从这里恢复'
  })
  const dir = picked.filePaths[0]
  if (picked.canceled || !dir) return { canceled: true, ok: false }

  let data: LibraryFile
  try {
    data = await readBackup(dir)
  } catch (err) {
    logger.warn('backup', `读取备份失败：${redactPath(dir)}`, err)
    return {
      canceled: false,
      ok: false,
      error: '这个文件夹里没有可用的 library.json，请选择备份目录本身'
    }
  }

  try {
    const coversFrom = path.join(dir, COVERS_DIR)
    return mode === 'replace'
      ? await replaceWithBackup(data, coversFrom)
      : await mergeBackup(data, coversFrom)
  } catch (err) {
    logger.error('backup', '恢复失败', err)
    return {
      canceled: false,
      ok: false,
      error: `恢复失败：${err instanceof Error ? err.message : String(err)}`
    }
  }
}
