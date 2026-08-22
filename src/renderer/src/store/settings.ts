import { create } from 'zustand'
import { DEFAULT_SETTINGS, type AppSettings, type ThemeMode } from '@shared/types'

interface SettingsState {
  settings: AppSettings
  loaded: boolean
  load: () => Promise<void>
  update: (patch: Partial<AppSettings>) => Promise<void>
  /** 主进程已经写好并返回了整份设置（如添加库根目录）时直接替换 */
  replace: (settings: AppSettings) => void
}

export const useSettings = create<SettingsState>()((set) => ({
  settings: { ...DEFAULT_SETTINGS },
  loaded: false,

  load: async () => {
    const settings = await window.api.getSettings()
    set({ settings, loaded: true })
  },

  update: async (patch) => {
    // 先本地生效保证界面即时响应，再等主进程确认后覆盖
    set((s) => ({ settings: { ...s.settings, ...patch } }))
    const saved = await window.api.saveSettings(patch)
    set({ settings: saved })
  },

  replace: (settings) => set({ settings })
}))

/** 把主题设置落到 DOM（data-theme 驱动 CSS 变量） */
export function applyTheme(theme: ThemeMode): void {
  const dark =
    theme === 'dark' ||
    (theme === 'system' && window.matchMedia('(prefers-color-scheme: dark)').matches)
  document.documentElement.dataset.theme = dark ? 'dark' : 'light'
}

export function resolvedThemeIsDark(theme: ThemeMode): boolean {
  return (
    theme === 'dark' ||
    (theme === 'system' && window.matchMedia('(prefers-color-scheme: dark)').matches)
  )
}
