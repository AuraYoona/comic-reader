import { promises as fsp } from 'node:fs'
import path from 'node:path'
import { BrowserWindow, dialog, ipcMain, shell, type OpenDialogOptions } from 'electron'
import { IPC } from '@shared/ipc'
import type { ImportKind } from '@shared/api'
import type { Comic, OpenComicResult, ProgressPatch, SourceCheck } from '@shared/types'
import { SourceError, getPageList, invalidateComic, sourceExists } from './archive'
import { expandBatchRoot, importPaths, regenerateCover } from './importer'
import { logger } from './lib/logger'
import { db } from './store/db'

type GetWindow = () => BrowserWindow | null

function sourceErrorMessage(err: unknown, prefix: string): string {
  return err instanceof SourceError
    ? err.message
    : `${prefix}：${err instanceof Error ? err.message : String(err)}`
}

export function registerIpcHandlers(getWindow: GetWindow): void {
  // ---------- 导入 ----------

  ipcMain.handle(IPC.ImportSelect, async (_e, kind: ImportKind) => {
    const win = getWindow()
    if (!win) return []

    if (kind === 'batch') {
      const picked = await dialog.showOpenDialog(win, {
        title: '选择漫画库根目录（每个子文件夹或压缩包作为一本漫画）',
        properties: ['openDirectory']
      })
      const root = picked.filePaths[0]
      if (picked.canceled || !root) return []
      const targets = await expandBatchRoot(root)
      if (targets === null) {
        return [{ path: root, status: 'failed', reason: '无法读取该文件夹，请检查权限' }]
      }
      if (targets.length === 0) {
        return [{ path: root, status: 'failed', reason: '目录下没有子文件夹或 ZIP/CBZ 压缩包' }]
      }
      return importPaths(targets, (p) => win.webContents.send(IPC.ImportProgress, p))
    }

    const options: OpenDialogOptions =
      kind === 'folder'
        ? {
            title: '选择漫画文件夹（可多选）',
            properties: ['openDirectory', 'multiSelections']
          }
        : {
            title: '选择漫画压缩包（可多选）',
            filters: [{ name: '漫画压缩包 (ZIP / CBZ)', extensions: ['zip', 'cbz'] }],
            properties: ['openFile', 'multiSelections']
          }
    const result = await dialog.showOpenDialog(win, options)
    if (result.canceled || result.filePaths.length === 0) return []
    return importPaths(result.filePaths, (p) => win.webContents.send(IPC.ImportProgress, p))
  })

  ipcMain.handle(IPC.ImportPaths, async (_e, paths: unknown) => {
    const win = getWindow()
    if (!Array.isArray(paths)) return []
    const valid = paths.filter((p): p is string => typeof p === 'string' && p.length > 0)
    return importPaths(valid, (p) => win?.webContents.send(IPC.ImportProgress, p))
  })

  // ---------- 书架 ----------

  ipcMain.handle(IPC.LibraryGet, () => db.listComics())

  ipcMain.handle(IPC.LibraryRemove, async (_e, id: unknown) => {
    if (typeof id !== 'string') return
    const comic = db.getComic(id)
    if (!comic) return
    if (comic.coverFile) {
      await fsp.rm(path.join(db.coversDir(), comic.coverFile), { force: true }).catch(() => {})
    }
    invalidateComic(id)
    db.removeComic(id) // 只删记录，不动原文件
    logger.info('library', `移除《${comic.title}》（保留原文件：${comic.sourcePath}）`)
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
    return db.updateComic(id, upd)
  })

  /** 分批 stat 所有来源，限制并发避免一次打开太多句柄 */
  ipcMain.handle(IPC.LibraryVerify, async (): Promise<SourceCheck[]> => {
    const comics = db.listComics()
    const out: SourceCheck[] = []
    const CHUNK = 24
    for (let i = 0; i < comics.length; i += CHUNK) {
      const part = comics.slice(i, i + CHUNK)
      const flags = await Promise.all(part.map((c) => sourceExists(c.sourcePath)))
      part.forEach((c, j) => out.push({ id: c.id, missing: !flags[j] }))
    }
    const missing = out.filter((o) => o.missing).length
    if (missing > 0) logger.warn('library', `来源校验：${missing}/${comics.length} 本来源丢失`)
    return out
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
      logger.warn('reader', `打开《${comic.title}》失败`, err)
      return { ok: false, error: sourceErrorMessage(err, '打开失败') }
    }
  })

  ipcMain.handle(IPC.ComicRescan, async (_e, id: unknown): Promise<OpenComicResult> => {
    if (typeof id !== 'string') return { ok: false, error: '参数错误' }
    const comic = db.getComic(id)
    if (!comic) return { ok: false, error: '漫画不存在' }
    try {
      invalidateComic(id)
      const pages = await getPageList(comic)
      if (pages.length === 0) {
        return { ok: false, error: `来源中没有找到图片：${comic.sourcePath}` }
      }
      const patch: Partial<Omit<Comic, 'reader'>> = { pageCount: pages.length }
      if (comic.lastReadPage >= pages.length) {
        patch.lastReadPage = Math.max(0, pages.length - 1)
      }
      const cover = await regenerateCover(comic, pages[0])
      if (cover) patch.coverFile = cover
      const updated = db.updateComic(id, patch)!
      logger.info('library', `重新扫描《${comic.title}》：${pages.length} 页`)
      return { ok: true, comic: updated, pageCount: pages.length }
    } catch (err) {
      logger.warn('library', `重新扫描《${comic.title}》失败`, err)
      return { ok: false, error: sourceErrorMessage(err, '重新扫描失败') }
    }
  })

  ipcMain.handle(IPC.ComicReveal, (_e, id: unknown) => {
    if (typeof id !== 'string') return
    const comic = db.getComic(id)
    if (comic) shell.showItemInFolder(comic.sourcePath)
  })

  // ---------- 设置 ----------

  ipcMain.handle(IPC.SettingsGet, () => db.getSettings())

  ipcMain.handle(IPC.SettingsSave, (_e, patch: unknown) =>
    db.saveSettings(patch && typeof patch === 'object' ? (patch as never) : {})
  )

  // ---------- 窗口 ----------

  ipcMain.handle(IPC.WindowSetFullscreen, (_e, flag: unknown) => {
    getWindow()?.setFullScreen(flag === true)
  })

  ipcMain.handle(IPC.WindowIsFullscreen, () => getWindow()?.isFullScreen() ?? false)
}
