import { contextBridge, ipcRenderer, webUtils } from 'electron'
import { IPC } from '@shared/ipc'
import type { ImportProgress, RendererApi, UpdateEvent } from '@shared/api'

function subscribe<T>(channel: string, cb: (payload: T) => void): () => void {
  const listener = (_e: Electron.IpcRendererEvent, payload: T): void => cb(payload)
  ipcRenderer.on(channel, listener)
  return () => {
    ipcRenderer.removeListener(channel, listener)
  }
}

const api: RendererApi = {
  importSelect: (kind) => ipcRenderer.invoke(IPC.ImportSelect, kind),
  importPaths: (paths) => ipcRenderer.invoke(IPC.ImportPaths, paths),
  onImportProgress: (cb) => subscribe<ImportProgress>(IPC.ImportProgress, cb),

  getLibrary: () => ipcRenderer.invoke(IPC.LibraryGet),
  removeComic: (id) => ipcRenderer.invoke(IPC.LibraryRemove, id),
  removeComics: (ids) => ipcRenderer.invoke(IPC.LibraryRemoveMany, ids),
  updateProgress: (id, patch) => ipcRenderer.invoke(IPC.LibraryUpdateProgress, id, patch),
  verifyLibrary: () => ipcRenderer.invoke(IPC.LibraryVerify),
  renameComic: (id, title) => ipcRenderer.invoke(IPC.LibraryRename, id, title),
  relocateComics: (ids) => ipcRenderer.invoke(IPC.LibraryRelocate, ids),

  openComic: (id) => ipcRenderer.invoke(IPC.ComicOpen, id),
  revealComic: (id) => ipcRenderer.invoke(IPC.ComicReveal, id),
  rescanComic: (id) => ipcRenderer.invoke(IPC.ComicRescan, id),
  rescanComics: (ids) => ipcRenderer.invoke(IPC.ComicRescanMany, ids),

  getSettings: () => ipcRenderer.invoke(IPC.SettingsGet),
  saveSettings: (patch) => ipcRenderer.invoke(IPC.SettingsSave, patch),

  backupLibrary: () => ipcRenderer.invoke(IPC.LibraryBackup),
  restoreLibrary: (mode) => ipcRenderer.invoke(IPC.LibraryRestore, mode),
  scanLibraryRoots: () => ipcRenderer.invoke(IPC.LibraryScanRoots),
  addLibraryRoot: () => ipcRenderer.invoke(IPC.LibraryAddRoot),

  listCategories: () => ipcRenderer.invoke(IPC.CategoryList),
  createCategory: (name, color) => ipcRenderer.invoke(IPC.CategoryCreate, name, color),
  updateCategory: (id, patch) => ipcRenderer.invoke(IPC.CategoryUpdate, id, patch),
  deleteCategory: (id) => ipcRenderer.invoke(IPC.CategoryDelete, id),
  toggleComicCategory: (id, categoryId) =>
    ipcRenderer.invoke(IPC.ComicToggleCategory, id, categoryId),
  toggleComicCategoryMany: (ids, categoryId, add) =>
    ipcRenderer.invoke(IPC.ComicToggleCategoryMany, ids, categoryId, add),

  toggleBookmark: (id, page) => ipcRenderer.invoke(IPC.ComicToggleBookmark, id, page),

  // Uint8Array 走结构化克隆，不经过 JSON，几十 KB 的封面开销可以忽略
  saveCoverThumbnail: (id, jpeg) => ipcRenderer.invoke(IPC.CoverSaveThumb, id, jpeg),

  setFullscreen: (flag) => ipcRenderer.invoke(IPC.WindowSetFullscreen, flag),
  isFullscreen: () => ipcRenderer.invoke(IPC.WindowIsFullscreen),
  onFullscreenChange: (cb) => subscribe<boolean>(IPC.WindowFullscreenChanged, cb),

  checkForUpdates: () => ipcRenderer.invoke(IPC.UpdateCheck),
  downloadUpdate: () => ipcRenderer.invoke(IPC.UpdateDownload),
  installUpdate: () => ipcRenderer.invoke(IPC.UpdateInstall),
  getAppVersion: () => ipcRenderer.invoke(IPC.UpdateGetVersion),
  onUpdateEvent: (cb) => subscribe<UpdateEvent>(IPC.UpdateEvent, cb),

  pathForFile: (file) => webUtils.getPathForFile(file)
}

contextBridge.exposeInMainWorld('api', api)
