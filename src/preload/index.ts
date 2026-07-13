import { contextBridge, ipcRenderer, webUtils } from 'electron'
import { IPC } from '@shared/ipc'
import type { ImportProgress, RendererApi } from '@shared/api'

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
  updateProgress: (id, patch) => ipcRenderer.invoke(IPC.LibraryUpdateProgress, id, patch),
  verifyLibrary: () => ipcRenderer.invoke(IPC.LibraryVerify),

  openComic: (id) => ipcRenderer.invoke(IPC.ComicOpen, id),
  revealComic: (id) => ipcRenderer.invoke(IPC.ComicReveal, id),
  rescanComic: (id) => ipcRenderer.invoke(IPC.ComicRescan, id),

  getSettings: () => ipcRenderer.invoke(IPC.SettingsGet),
  saveSettings: (patch) => ipcRenderer.invoke(IPC.SettingsSave, patch),

  setFullscreen: (flag) => ipcRenderer.invoke(IPC.WindowSetFullscreen, flag),
  isFullscreen: () => ipcRenderer.invoke(IPC.WindowIsFullscreen),
  onFullscreenChange: (cb) => subscribe<boolean>(IPC.WindowFullscreenChanged, cb),

  pathForFile: (file) => webUtils.getPathForFile(file)
}

contextBridge.exposeInMainWorld('api', api)
