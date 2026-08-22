import { create } from 'zustand'
import type { UpdateEvent } from '@shared/api'
import { useUi } from './ui'

export type UpdateStatus =
  'idle' | 'checking' | 'available' | 'not-available' | 'downloading' | 'downloaded' | 'error'

interface UpdaterState {
  status: UpdateStatus
  /** 新版本号（available / downloaded 之后有值） */
  version: string | null
  /** 下载进度 0-100 */
  percent: number
  error: string | null
  /** 本次检查是否由用户在设置里手动发起（决定“已是最新版本”这类反馈是否弹 toast） */
  manual: boolean
  check: (manual: boolean) => Promise<void>
  download: () => Promise<void>
  install: () => Promise<void>
  handleEvent: (e: UpdateEvent) => void
}

export const useUpdater = create<UpdaterState>()((set, get) => ({
  status: 'idle',
  version: null,
  percent: 0,
  error: null,
  manual: false,

  check: async (manual) => {
    set({ manual, error: null })
    const started = await window.api.checkForUpdates()
    if (!started && manual) {
      useUi.getState().toast('当前环境不支持自动更新（开发模式或便携版）', 'info')
    }
  },

  download: async () => {
    set({ status: 'downloading', percent: 0, error: null })
    await window.api.downloadUpdate()
  },

  install: async () => {
    await window.api.installUpdate()
  },

  handleEvent: (e) => {
    const { manual, status } = get()
    switch (e.type) {
      case 'checking':
        set({ status: 'checking', error: null })
        break
      case 'available':
        set({ status: 'available', version: e.version, manual: false })
        if (!manual) {
          useUi.getState().toast(`发现新版本 v${e.version}，可在设置中更新`, 'info')
        }
        break
      case 'not-available':
        set({ status: 'not-available', manual: false })
        if (manual) useUi.getState().toast('已是最新版本', 'success')
        break
      case 'downloading':
        set({ status: 'downloading', percent: e.percent })
        break
      case 'downloaded':
        set({ status: 'downloaded', version: e.version, percent: 100 })
        break
      case 'error': {
        const downloading = status === 'downloading'
        set({ status: 'error', error: e.message, manual: false })
        // 下载失败无论如何都要告知；检查失败只在手动检查时提示，自动检查静默
        if (downloading) useUi.getState().toast(`下载更新失败：${e.message}`, 'error')
        else if (manual) useUi.getState().toast(`检查更新失败：${e.message}`, 'error')
        break
      }
    }
  }
}))
