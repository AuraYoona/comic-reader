import { app, type BrowserWindow } from 'electron'
import electronUpdater from 'electron-updater'
import { IPC } from '@shared/ipc'
import type { UpdateEvent } from '@shared/api'
import { logger } from './lib/logger'

const { autoUpdater } = electronUpdater

type GetWindow = () => BrowserWindow | null

let getWindow: GetWindow = () => null
let initialized = false

/**
 * 便携版（portable）没有安装目录，electron-updater 无法替换自身，只有安装版支持更新。
 * electron-builder 的 portable 启动器会设置 PORTABLE_EXECUTABLE_DIR。
 */
export function updateSupported(): boolean {
  return app.isPackaged && !process.env['PORTABLE_EXECUTABLE_DIR']
}

function send(e: UpdateEvent): void {
  const win = getWindow()
  if (win && !win.isDestroyed()) win.webContents.send(IPC.UpdateEvent, e)
}

export function initUpdater(getWin: GetWindow): void {
  getWindow = getWin
  if (!updateSupported() || initialized) return
  initialized = true

  autoUpdater.logger = null
  autoUpdater.autoDownload = false // 下载由用户在界面里确认后发起
  autoUpdater.autoInstallOnAppQuit = true // 下载完成后即使用户不点“重启安装”，退出时也会装上

  autoUpdater.on('checking-for-update', () => send({ type: 'checking' }))
  autoUpdater.on('update-available', (info) => {
    logger.info('updater', `发现新版本 v${info.version}（当前 v${app.getVersion()}）`)
    send({ type: 'available', version: info.version })
  })
  autoUpdater.on('update-not-available', () => send({ type: 'not-available' }))
  autoUpdater.on('download-progress', (p) => {
    send({ type: 'downloading', percent: Math.max(0, Math.min(100, p.percent)) })
  })
  autoUpdater.on('update-downloaded', (info) => {
    logger.info('updater', `新版本 v${info.version} 下载完成，等待安装`)
    send({ type: 'downloaded', version: info.version })
  })
  autoUpdater.on('error', (err) => {
    logger.warn('updater', '更新出错', err)
    send({ type: 'error', message: err.message })
  })
}

/** 检查更新；返回是否真正发起了检查（开发模式/便携版返回 false） */
export function checkForUpdates(): boolean {
  if (!updateSupported()) return false
  void autoUpdater.checkForUpdates().catch(() => {
    // 网络错误已经通过 error 事件推给渲染进程，这里只需吞掉拒绝避免 unhandledRejection
  })
  return true
}

export function downloadUpdate(): void {
  if (!updateSupported()) return
  void autoUpdater.downloadUpdate().catch(() => {})
}

export function installUpdate(): void {
  if (!updateSupported()) return
  // before-quit 里会 flushSync 落盘，quitAndInstall 会正常走 quit 流程
  autoUpdater.quitAndInstall()
}
