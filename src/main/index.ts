import path from 'node:path'
import { app, BrowserWindow, Menu } from 'electron'
import { IPC } from '@shared/ipc'
import { closeAllSources } from './archive'
import { registerIpcHandlers } from './ipc'
import { logger } from './lib/logger'
import { registerComicProtocolHandler, registerComicSchemePrivileges } from './protocol'
import { db } from './store/db'
import { windowState } from './store/windowState'
import { checkForUpdates, initUpdater } from './updater'

// 必须在 app ready 之前注册特权 scheme
registerComicSchemePrivileges()

let mainWindow: BrowserWindow | null = null

function createWindow(): void {
  const bounds = windowState.getCreateBounds()
  const win = new BrowserWindow({
    ...bounds,
    minWidth: 960,
    minHeight: 600,
    show: false,
    autoHideMenuBar: true,
    backgroundColor: '#151519', // 避免启动白闪
    title: '漫画阅读器',
    webPreferences: {
      preload: path.join(__dirname, '../preload/index.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  })
  mainWindow = win
  if (windowState.wasMaximized()) win.maximize()
  windowState.track(win)

  win.on('ready-to-show', () => win.show())
  win.on('closed', () => {
    mainWindow = null
  })

  // ---- 安全加固：本应用从不需要打开新窗口 / 站外导航 / 任何 Web 权限 ----
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }))
  const devUrl = process.env['ELECTRON_RENDERER_URL']
  win.webContents.on('will-navigate', (e, url) => {
    const allowed =
      (!app.isPackaged && devUrl && url.startsWith(devUrl)) || url.startsWith('file://')
    if (!allowed) {
      logger.warn('security', `已拦截页面导航：${url}`)
      e.preventDefault()
    }
  })
  win.webContents.session.setPermissionRequestHandler((_wc, permission, callback) => {
    logger.warn('security', `已拒绝权限请求：${permission}`)
    callback(false)
  })

  // 全屏状态同步给渲染进程（阅读器工具栏图标用）
  const sendFs = (flag: boolean) => () => {
    if (!win.isDestroyed()) win.webContents.send(IPC.WindowFullscreenChanged, flag)
  }
  win.on('enter-full-screen', sendFs(true))
  win.on('leave-full-screen', sendFs(false))

  // 菜单栏对这个应用没有意义，去掉换来干净的桌面观感；开发时保留 F12 开调试器
  if (!app.isPackaged) {
    win.webContents.on('before-input-event', (_e, input) => {
      if (input.type === 'keyDown' && input.key === 'F12') {
        win.webContents.toggleDevTools()
      }
    })
  }

  if (!app.isPackaged && devUrl) {
    void win.loadURL(devUrl)
  } else {
    void win.loadFile(path.join(__dirname, '../renderer/index.html'))
  }
}

const gotLock = app.requestSingleInstanceLock()
if (!gotLock) {
  app.quit()
} else {
  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore()
      mainWindow.focus()
    }
  })

  app.whenReady().then(() => {
    logger.init(app.getPath('userData'))
    Menu.setApplicationMenu(null)
    db.init()
    windowState.init()
    registerComicProtocolHandler()
    registerIpcHandlers(() => mainWindow)
    createWindow()
    initUpdater(() => mainWindow)

    // 启动后延迟几秒再检查更新，避免抢占首屏加载的网络与磁盘
    if (db.getSettings().autoCheckUpdates) {
      setTimeout(() => checkForUpdates(), 4000)
    }

    app.on('activate', () => {
      if (BrowserWindow.getAllWindows().length === 0) createWindow()
    })
  })
}

// 兜底：任何未捕获异常都进日志，不让主进程静默崩溃
process.on('uncaughtException', (err) => {
  logger.error('process', '未捕获异常', err)
})
process.on('unhandledRejection', (reason) => {
  logger.error('process', '未处理的 Promise 拒绝', reason)
})

app.on('window-all-closed', () => {
  app.quit()
})

app.on('before-quit', () => {
  db.flushSync()
  closeAllSources()
  logger.close()
})
