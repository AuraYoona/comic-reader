import { promises as fsp } from 'node:fs'
import path from 'node:path'
import { app, type BrowserWindow, dialog, ipcMain, shell, type OpenDialogOptions } from 'electron'
import { IPC } from '@shared/ipc'
import type { ImportKind } from '@shared/api'
import {
  CATEGORY_NAME_MAX,
  TITLE_MAX,
  type BackupResult,
  type BatchRescanResult,
  type CategoryMutationResult,
  type CategoryPatch,
  type Comic,
  type OpenComicResult,
  type ProgressPatch,
  type RelocateResult,
  type RenameResult,
  type RestoreResult,
  type ScanRootsResult,
  type SourceCheck
} from '@shared/types'
import {
  ARCHIVE_FILTER_EXTS,
  SourceError,
  getPageList,
  invalidateComic,
  releaseSource,
  sourceExists
} from './archive'
import { backupLibrary, restoreLibrary } from './backup'
import { expandBatchRoot, findUnimportedInRoot, importPaths, regenerateCover } from './importer'
import { logger } from './lib/logger'
import { clearThumbCache } from './protocol'
import { relocateUnderRoot } from './relocate'
import { db } from './store/db'
import { isJpegBuffer } from './thumbnail'
import { comicRef, redactPath } from './utils/redact'
import { checkForUpdates, downloadUpdate, installUpdate } from './updater'

type GetWindow = () => BrowserWindow | null

/** 渲染进程回传封面的体积上限：480px 宽的 JPEG 远小于此，超出的一律拒收 */
const COVER_UPLOAD_MAX_BYTES = 2 * 1024 * 1024

/** stat 并发上限，避免一次打开太多句柄 */
const VERIFY_CHUNK = 24

function sourceErrorMessage(err: unknown, prefix: string): string {
  return err instanceof SourceError
    ? err.message
    : `${prefix}：${err instanceof Error ? err.message : String(err)}`
}

function stringList(raw: unknown): string[] {
  return Array.isArray(raw) ? raw.filter((v): v is string => typeof v === 'string' && !!v) : []
}

/** 丢掉某本漫画的全部运行时缓存（页面列表、压缩包句柄、缩略图） */
function forgetComic(comic: Comic): void {
  invalidateComic(comic.id)
  clearThumbCache(comic.id)
  if (comic.sourceType === 'archive') releaseSource(comic.sourcePath)
}

async function removeCoverFile(coverFile: string | null): Promise<void> {
  if (!coverFile) return
  await fsp.rm(path.join(db.coversDir(), path.basename(coverFile)), { force: true }).catch(() => {})
}

/** 分批检查来源是否还在 */
async function checkSources(comics: Comic[]): Promise<SourceCheck[]> {
  const out: SourceCheck[] = []
  for (let i = 0; i < comics.length; i += VERIFY_CHUNK) {
    const part = comics.slice(i, i + VERIFY_CHUNK)
    const flags = await Promise.all(part.map((c) => sourceExists(c.sourcePath)))
    part.forEach((c, j) => out.push({ id: c.id, missing: !flags[j] }))
  }
  return out
}

/** 重新扫描一本：刷新页数与封面。返回 null 表示记录不存在。 */
async function rescanOne(id: string): Promise<OpenComicResult> {
  const comic = db.getComic(id)
  if (!comic) return { ok: false, error: '漫画不存在' }
  try {
    forgetComic(comic)
    const pages = await getPageList(comic)
    if (pages.length === 0) {
      return { ok: false, error: `来源中没有找到图片：${comic.sourcePath}` }
    }
    const patch: Partial<Omit<Comic, 'reader'>> = { pageCount: pages.length }
    if (comic.lastReadPage >= pages.length) {
      patch.lastReadPage = Math.max(0, pages.length - 1)
    }
    // 书签可能指向已经不存在的页
    const valid = comic.bookmarks.filter((p) => p < pages.length)
    if (valid.length !== comic.bookmarks.length) patch.bookmarks = valid
    const cover = await regenerateCover(comic, pages[0])
    if (cover) patch.coverFile = cover
    const updated = db.updateComic(id, patch)!
    return { ok: true, comic: updated, pageCount: pages.length }
  } catch (err) {
    logger.warn('library', `重新扫描 ${comicRef(comic.id)} 失败`, err)
    return { ok: false, error: sourceErrorMessage(err, '重新扫描失败') }
  }
}

/**
 * 扫描已记录的库根目录，把新出现的子文件夹 / 压缩包自动上架。
 * 由渲染进程在书架加载完成后触发，这样能复用导入进度提示。
 */
async function scanLibraryRoots(win: BrowserWindow | null): Promise<ScanRootsResult> {
  const roots = db.getSettings().libraryRoots
  const added: Comic[] = []
  const unreadable: string[] = []
  for (const root of roots) {
    const targets = await findUnimportedInRoot(root)
    if (targets === null) {
      unreadable.push(root)
      continue
    }
    if (targets.length === 0) continue
    const results = await importPaths(targets, (p) =>
      win && !win.isDestroyed() ? win.webContents.send(IPC.ImportProgress, p) : undefined
    )
    for (const r of results) {
      if (r.status === 'imported' && r.comic) added.push(r.comic)
    }
  }
  if (added.length > 0 || unreadable.length > 0) {
    logger.info(
      'library',
      `库根目录扫描：${roots.length} 个根目录，自动上架 ${added.length} 本，${unreadable.length} 个读不了`
    )
  }
  return { roots: roots.length, added, unreadable }
}

export function registerIpcHandlers(getWindow: GetWindow): void {
  // ---------- 导入 ----------

  ipcMain.handle(IPC.ImportSelect, async (_e, kind: ImportKind) => {
    const win = getWindow()
    if (!win) return []

    if (kind === 'batch') {
      const picked = await dialog.showOpenDialog(win, {
        title: '选择漫画库根目录（每个子文件夹、压缩包或 PDF 作为一本漫画）',
        properties: ['openDirectory']
      })
      const root = picked.filePaths[0]
      if (picked.canceled || !root) return []
      const targets = await expandBatchRoot(root)
      if (targets === null) {
        return [{ path: root, status: 'failed', reason: '无法读取该文件夹，请检查权限' }]
      }
      if (targets.length === 0) {
        return [{ path: root, status: 'failed', reason: '目录下没有子文件夹或受支持的漫画文件' }]
      }
      // 记住这个根目录，之后可以增量扫描出新加进来的漫画
      db.addLibraryRoot(root)
      return importPaths(targets, (p) => win.webContents.send(IPC.ImportProgress, p))
    }

    const options: OpenDialogOptions =
      kind === 'folder'
        ? {
            title: '选择漫画文件夹（可多选）',
            properties: ['openDirectory', 'multiSelections']
          }
        : {
            title: '选择漫画文件（可多选）',
            filters: [
              {
                name: '漫画文件 (ZIP / CBZ / RAR / CBR / PDF)',
                extensions: [...ARCHIVE_FILTER_EXTS]
              }
            ],
            properties: ['openFile', 'multiSelections']
          }
    const result = await dialog.showOpenDialog(win, options)
    if (result.canceled || result.filePaths.length === 0) return []
    return importPaths(result.filePaths, (p) => win.webContents.send(IPC.ImportProgress, p))
  })

  ipcMain.handle(IPC.ImportPaths, async (_e, paths: unknown) => {
    const win = getWindow()
    const valid = stringList(paths)
    if (valid.length === 0) return []
    return importPaths(valid, (p) => win?.webContents.send(IPC.ImportProgress, p))
  })

  // ---------- 书架 ----------

  ipcMain.handle(IPC.LibraryGet, () => db.listComics())

  ipcMain.handle(IPC.LibraryRemove, async (_e, id: unknown) => {
    if (typeof id !== 'string') return
    const comic = db.getComic(id)
    if (!comic) return
    await removeCoverFile(comic.coverFile)
    forgetComic(comic)
    db.removeComic(id) // 只删记录，不动原文件
    logger.info(
      'library',
      `移除 ${comicRef(comic.id)}（原文件保留在 ${redactPath(comic.sourcePath)}）`
    )
  })

  ipcMain.handle(IPC.LibraryRemoveMany, async (_e, ids: unknown): Promise<string[]> => {
    const list = stringList(ids)
    if (list.length === 0) return []
    const comics = list.map((id) => db.getComic(id)).filter((c): c is Comic => !!c)
    for (const comic of comics) {
      await removeCoverFile(comic.coverFile)
      forgetComic(comic)
    }
    const removed = db.removeComics(comics.map((c) => c.id))
    if (removed.length > 0) {
      logger.info('library', `批量移除 ${removed.length} 本（原文件均保留）`)
    }
    return removed
  })

  ipcMain.handle(IPC.LibraryUpdateProgress, (_e, id: unknown, patch: ProgressPatch) => {
    if (typeof id !== 'string' || !patch || typeof patch !== 'object') return null
    const comic = db.getComic(id)
    if (!comic) return null
    const upd: Partial<Omit<Comic, 'reader'>> & { reader?: ProgressPatch['reader'] } = {}
    if (typeof patch.lastReadPage === 'number' && Number.isFinite(patch.lastReadPage)) {
      const max = Math.max(0, comic.pageCount - 1)
      upd.lastReadPage = Math.min(Math.max(0, Math.round(patch.lastReadPage)), max)
      upd.lastReadAt = Date.now()
    }
    if (patch.reader && typeof patch.reader === 'object') {
      upd.reader = patch.reader
    }
    // 进度走长防抖：翻页非常频繁，退出前的 flushSync 兜底，不会丢
    return db.updateComic(id, upd, { lazy: true })
  })

  ipcMain.handle(IPC.LibraryVerify, async (): Promise<SourceCheck[]> => {
    const comics = db.listComics()
    const out = await checkSources(comics)
    const missing = out.filter((o) => o.missing).length
    if (missing > 0) logger.warn('library', `来源校验：${missing}/${comics.length} 本来源丢失`)
    return out
  })

  ipcMain.handle(IPC.LibraryRename, (_e, id: unknown, title: unknown): RenameResult => {
    if (typeof id !== 'string' || typeof title !== 'string') return { ok: false, error: '参数错误' }
    const trimmed = title.trim()
    if (!trimmed) return { ok: false, error: '标题不能为空' }
    if (trimmed.length > TITLE_MAX) return { ok: false, error: `标题不能超过 ${TITLE_MAX} 个字符` }
    const comic = db.renameComic(id, trimmed)
    if (!comic) return { ok: false, error: '漫画不存在，可能已被移除' }
    logger.info('library', `重命名 ${comicRef(comic.id)}（原文件未改名）`)
    return { ok: true, comic }
  })

  ipcMain.handle(IPC.LibraryRelocate, async (_e, ids: unknown): Promise<RelocateResult> => {
    const win = getWindow()
    if (!win) return { canceled: true, relocated: [], unmatched: 0 }

    const list = stringList(ids)
    let targets: Comic[]
    if (list.length > 0) {
      targets = list.map((id) => db.getComic(id)).filter((c): c is Comic => !!c)
    } else {
      // 没指定就处理所有来源已丢失的记录
      const checks = await checkSources(db.listComics())
      const missing = new Set(checks.filter((c) => c.missing).map((c) => c.id))
      targets = db.listComics().filter((c) => missing.has(c.id))
    }
    if (targets.length === 0) {
      return { canceled: false, relocated: [], unmatched: 0, error: '没有需要重新定位的漫画' }
    }

    const picked = await dialog.showOpenDialog(win, {
      title: '选择漫画库的新位置（会在其中按文件名查找）',
      properties: ['openDirectory'],
      buttonLabel: '在这里查找'
    })
    const root = picked.filePaths[0]
    if (picked.canceled || !root) return { canceled: true, relocated: [], unmatched: 0 }

    try {
      const outcome = await relocateUnderRoot(root, targets)
      for (const comic of outcome.relocated) forgetComic(comic)
      return {
        canceled: false,
        root,
        relocated: outcome.relocated,
        unmatched: outcome.unmatched
      }
    } catch (err) {
      logger.error('library', '来源重定位失败', err)
      return {
        canceled: false,
        root,
        relocated: [],
        unmatched: targets.length,
        error: sourceErrorMessage(err, '重新定位失败')
      }
    }
  })

  ipcMain.handle(IPC.LibraryBackup, (): Promise<BackupResult> => backupLibrary(getWindow()))

  ipcMain.handle(IPC.LibraryRestore, async (_e, mode: unknown): Promise<RestoreResult> => {
    const target = mode === 'replace' ? 'replace' : 'merge'
    const result = await restoreLibrary(getWindow(), target)
    if (result.ok) clearThumbCache()
    return result
  })

  ipcMain.handle(IPC.LibraryScanRoots, (): Promise<ScanRootsResult> =>
    scanLibraryRoots(getWindow())
  )

  ipcMain.handle(IPC.LibraryAddRoot, async () => {
    const win = getWindow()
    if (!win) return db.getSettings()
    const picked = await dialog.showOpenDialog(win, {
      title: '选择漫画库根目录（启动时会自动扫描其中的新漫画）',
      properties: ['openDirectory']
    })
    const root = picked.filePaths[0]
    if (picked.canceled || !root) return db.getSettings()
    return db.addLibraryRoot(root)
  })

  // ---------- 阅读 ----------

  ipcMain.handle(IPC.ComicOpen, async (_e, id: unknown): Promise<OpenComicResult> => {
    if (typeof id !== 'string') return { ok: false, error: '参数错误' }
    const comic = db.getComic(id)
    if (!comic) return { ok: false, error: '漫画不存在，可能已被移除' }
    try {
      invalidateComic(id) // 强制重新扫描，来源在外部被增删过也能拿到最新页数
      const pages = await getPageList(comic)
      if (pages.length === 0) {
        return { ok: false, error: `来源中没有找到图片：${comic.sourcePath}` }
      }
      const patch: Partial<Omit<Comic, 'reader'>> = {
        pageCount: pages.length,
        lastReadAt: Date.now()
      }
      if (comic.lastReadPage >= pages.length) patch.lastReadPage = 0
      const updated = db.updateComic(id, patch)!
      db.saveSettings({ lastOpenedComicId: id })
      return { ok: true, comic: updated, pageCount: pages.length }
    } catch (err) {
      logger.warn('reader', `打开 ${comicRef(comic.id)} 失败`, err)
      return { ok: false, error: sourceErrorMessage(err, '打开失败') }
    }
  })

  ipcMain.handle(IPC.ComicRescan, async (_e, id: unknown): Promise<OpenComicResult> => {
    if (typeof id !== 'string') return { ok: false, error: '参数错误' }
    const result = await rescanOne(id)
    if (result.ok) logger.info('library', `重新扫描 ${comicRef(id)}：${result.pageCount} 页`)
    return result
  })

  ipcMain.handle(IPC.ComicRescanMany, async (_e, ids: unknown): Promise<BatchRescanResult> => {
    const win = getWindow()
    const list = stringList(ids)
    const out: BatchRescanResult = { updated: [], failed: [] }
    for (let i = 0; i < list.length; i++) {
      const comic = db.getComic(list[i])
      if (win && !win.isDestroyed()) {
        win.webContents.send(IPC.ImportProgress, {
          current: i + 1,
          total: list.length,
          path: comic?.title ?? list[i]
        })
      }
      const result = await rescanOne(list[i])
      if (result.ok && result.comic) out.updated.push(result.comic)
      else {
        out.failed.push({
          id: list[i],
          title: comic?.title ?? list[i],
          error: result.error ?? '重新扫描失败'
        })
      }
    }
    logger.info('library', `批量重新扫描：成功 ${out.updated.length}，失败 ${out.failed.length}`)
    return out
  })

  ipcMain.handle(IPC.ComicReveal, (_e, id: unknown) => {
    if (typeof id !== 'string') return
    const comic = db.getComic(id)
    if (comic) shell.showItemInFolder(comic.sourcePath)
  })

  ipcMain.handle(IPC.ComicToggleBookmark, (_e, id: unknown, page: unknown): Comic | null => {
    if (typeof id !== 'string' || typeof page !== 'number') return null
    const comic = db.getComic(id)
    if (!comic) return null
    if (page < 0 || page >= comic.pageCount) return comic
    return db.toggleBookmark(id, page)
  })

  // ---------- 封面 ----------

  /**
   * 渲染进程回传重新压缩过的封面。
   * 主进程的 nativeImage 只能解 PNG/JPEG，WebP/AVIF/GIF 首页会被原样当封面存下来，
   * 书架滚动时几百张几 MB 的原图很吃内存 —— 由渲染进程用 canvas 压成 480px 的 JPEG 换掉。
   * 字节来自渲染进程，落盘前必须校验类型与体积，且文件名一律由主进程生成。
   */
  ipcMain.handle(
    IPC.CoverSaveThumb,
    async (_e, id: unknown, jpeg: unknown): Promise<Comic | null> => {
      if (typeof id !== 'string') return null
      const comic = db.getComic(id)
      if (!comic) return null
      if (!(jpeg instanceof Uint8Array) || jpeg.byteLength === 0) return null
      if (jpeg.byteLength > COVER_UPLOAD_MAX_BYTES) {
        logger.warn('library', `拒收过大的封面缩略图：${jpeg.byteLength} 字节`)
        return null
      }
      const data = Buffer.from(jpeg.buffer, jpeg.byteOffset, jpeg.byteLength)
      if (!isJpegBuffer(data)) {
        logger.warn('library', '拒收非 JPEG 的封面缩略图')
        return null
      }
      const fileName = `${comic.id}-${Date.now()}.jpg`
      try {
        await fsp.mkdir(db.coversDir(), { recursive: true })
        await fsp.writeFile(path.join(db.coversDir(), fileName), data)
      } catch (err) {
        logger.warn('library', '写入封面缩略图失败', err)
        return null
      }
      const old = comic.coverFile
      const updated = db.updateComic(id, { coverFile: fileName })
      if (old && old !== fileName) await removeCoverFile(old)
      return updated
    }
  )

  // ---------- 设置 ----------

  ipcMain.handle(IPC.SettingsGet, () => db.getSettings())

  ipcMain.handle(IPC.SettingsSave, (_e, patch: unknown) =>
    db.saveSettings(patch && typeof patch === 'object' ? (patch as never) : {})
  )

  // ---------- 分类 ----------

  ipcMain.handle(IPC.CategoryList, () => db.listCategories())

  ipcMain.handle(
    IPC.CategoryCreate,
    (_e, name: unknown, color: unknown): CategoryMutationResult => {
      if (typeof name !== 'string') return { ok: false, error: '参数错误' }
      const trimmed = name.trim()
      if (!trimmed) return { ok: false, error: '名称不能为空' }
      if (trimmed.length > CATEGORY_NAME_MAX) return { ok: false, error: '名称过长' }
      if (db.listCategories().some((c) => c.name === trimmed)) {
        return { ok: false, error: '同名分类已存在' }
      }
      const category = db.createCategory(trimmed, typeof color === 'string' ? color : undefined)
      logger.info('library', `新建分类「${category.name}」`)
      return { ok: true, category }
    }
  )

  ipcMain.handle(IPC.CategoryUpdate, (_e, id: unknown, patch: unknown): CategoryMutationResult => {
    if (typeof id !== 'string' || !patch || typeof patch !== 'object') {
      return { ok: false, error: '参数错误' }
    }
    const raw = patch as Record<string, unknown>
    // 只把校验过的字段写库，不透传渲染进程传来的原始对象
    const vetted: CategoryPatch = {}
    if (typeof raw.name === 'string') {
      const trimmed = raw.name.trim()
      if (!trimmed) return { ok: false, error: '名称不能为空' }
      if (trimmed.length > CATEGORY_NAME_MAX) return { ok: false, error: '名称过长' }
      if (db.listCategories().some((c) => c.id !== id && c.name === trimmed)) {
        return { ok: false, error: '同名分类已存在' }
      }
      vetted.name = trimmed
    }
    if (typeof raw.color === 'string') vetted.color = raw.color
    const category = db.updateCategory(id, vetted)
    if (!category) return { ok: false, error: '分类不存在' }
    return { ok: true, category }
  })

  ipcMain.handle(IPC.CategoryDelete, (_e, id: unknown): boolean => {
    if (typeof id !== 'string') return false
    const removed = db.deleteCategory(id)
    if (removed) logger.info('library', `删除分类 ${id}（仅解除漫画关联）`)
    return removed
  })

  ipcMain.handle(IPC.ComicToggleCategory, (_e, id: unknown, categoryId: unknown): Comic | null => {
    if (typeof id !== 'string' || typeof categoryId !== 'string') return null
    return db.toggleComicCategory(id, categoryId)
  })

  ipcMain.handle(
    IPC.ComicToggleCategoryMany,
    (_e, ids: unknown, categoryId: unknown, add: unknown): Comic[] => {
      if (typeof categoryId !== 'string') return []
      const list = stringList(ids)
      if (list.length === 0) return []
      return db.setComicsCategory(list, categoryId, add === true)
    }
  )

  // ---------- 更新 ----------

  ipcMain.handle(IPC.UpdateCheck, () => checkForUpdates())
  ipcMain.handle(IPC.UpdateDownload, () => downloadUpdate())
  ipcMain.handle(IPC.UpdateInstall, () => installUpdate())
  ipcMain.handle(IPC.UpdateGetVersion, () => app.getVersion())

  // ---------- 窗口 ----------

  ipcMain.handle(IPC.WindowSetFullscreen, (_e, flag: unknown) => {
    getWindow()?.setFullScreen(flag === true)
  })

  ipcMain.handle(IPC.WindowIsFullscreen, () => getWindow()?.isFullScreen() ?? false)
}
