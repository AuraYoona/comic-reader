import fs from 'node:fs'
import path from 'node:path'
import { app, screen, type BrowserWindow } from 'electron'
import { logger } from '../lib/logger'

interface PersistedWindowState {
  width: number
  height: number
  x?: number
  y?: number
  maximized: boolean
}

const DEFAULTS: PersistedWindowState = { width: 1280, height: 820, maximized: false }
const MIN_VISIBLE = 100
const SAVE_DEBOUNCE_MS = 500

/**
 * 记住窗口大小/位置/最大化状态（window-state.json）。
 * 恢复时校验窗口至少有一角落在某块显示器内，防止拔掉外接屏后窗口"消失"。
 */
class WindowStateStore {
  private file = ''
  private state: PersistedWindowState = { ...DEFAULTS }
  private timer: NodeJS.Timeout | null = null

  init(): void {
    this.file = path.join(app.getPath('userData'), 'window-state.json')
    try {
      if (!fs.existsSync(this.file)) return
      const raw = JSON.parse(fs.readFileSync(this.file, 'utf-8')) as Partial<PersistedWindowState>
      if (
        typeof raw.width === 'number' &&
        raw.width >= 400 &&
        typeof raw.height === 'number' &&
        raw.height >= 300
      ) {
        this.state = {
          width: Math.round(raw.width),
          height: Math.round(raw.height),
          x: typeof raw.x === 'number' ? Math.round(raw.x) : undefined,
          y: typeof raw.y === 'number' ? Math.round(raw.y) : undefined,
          maximized: raw.maximized === true
        }
      }
    } catch (err) {
      logger.warn('window-state', '读取 window-state.json 失败，使用默认窗口大小', err)
      this.state = { ...DEFAULTS }
    }
  }

  /** 创建 BrowserWindow 用的边界（位置无效时交给系统居中） */
  getCreateBounds(): { width: number; height: number; x?: number; y?: number } {
    const { width, height, x, y } = this.state
    if (x === undefined || y === undefined || !this.isOnScreen(x, y, width, height)) {
      return { width, height }
    }
    return { width, height, x, y }
  }

  wasMaximized(): boolean {
    return this.state.maximized
  }

  private isOnScreen(x: number, y: number, w: number, h: number): boolean {
    return screen.getAllDisplays().some((d) => {
      const a = d.workArea
      return (
        x + w > a.x + MIN_VISIBLE &&
        x < a.x + a.width - MIN_VISIBLE &&
        y + MIN_VISIBLE > a.y - 20 && // 标题栏至少可见
        y < a.y + a.height - MIN_VISIBLE
      )
    })
  }

  /** 跟踪窗口变化，防抖记录，关闭时落盘 */
  track(win: BrowserWindow): void {
    const capture = (): void => {
      if (win.isDestroyed()) return
      const maximized = win.isMaximized()
      this.state.maximized = maximized
      if (!maximized && !win.isFullScreen() && !win.isMinimized()) {
        const b = win.getBounds()
        this.state = { ...this.state, width: b.width, height: b.height, x: b.x, y: b.y }
      }
    }
    const captureSoon = (): void => {
      if (this.timer) clearTimeout(this.timer)
      this.timer = setTimeout(capture, SAVE_DEBOUNCE_MS)
    }
    win.on('resize', captureSoon)
    win.on('move', captureSoon)
    win.on('maximize', capture)
    win.on('unmaximize', capture)
    win.on('close', () => {
      if (this.timer) clearTimeout(this.timer)
      capture()
      this.flush()
    })
  }

  private flush(): void {
    try {
      fs.writeFileSync(this.file, JSON.stringify(this.state, null, 2), 'utf-8')
    } catch (err) {
      logger.warn('window-state', '保存窗口状态失败', err)
    }
  }
}

export const windowState = new WindowStateStore()
