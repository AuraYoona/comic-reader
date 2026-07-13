import { create } from 'zustand'
import {
  clampZoomScale,
  type Comic,
  type ReadingDirection,
  type ReadingMode,
  type ZoomMode
} from '@shared/types'
import { clearPageCache } from '@/lib/pageCache'
import { useLibrary } from './library'
import { useSettings } from './settings'

interface ReaderState {
  /** 阅读器是否处于打开状态（含加载中/出错） */
  active: boolean
  opening: boolean
  error: string | null
  comic: Comic | null
  pageCount: number
  /** 0 起始页码 */
  page: number
  mode: ReadingMode
  zoom: ZoomMode
  scale: number
  direction: ReadingDirection

  open: (id: string, opts?: { fromStart?: boolean }) => Promise<void>
  close: () => void
  setPage: (n: number) => void
  next: () => void
  prev: () => void
  setMode: (m: ReadingMode) => void
  setZoom: (z: ZoomMode) => void
  setScale: (s: number) => void
  setDirection: (d: ReadingDirection) => void
}

const PERSIST_DEBOUNCE_MS = 400
let persistTimer: number | null = null

/** 把当前进度与阅读偏好写回主进程（防抖），并同步书架条目 */
function schedulePersist(): void {
  if (persistTimer !== null) window.clearTimeout(persistTimer)
  persistTimer = window.setTimeout(() => void flushPersist(), PERSIST_DEBOUNCE_MS)
}

async function flushPersist(): Promise<void> {
  if (persistTimer !== null) {
    window.clearTimeout(persistTimer)
    persistTimer = null
  }
  // 状态在任何 await 之前同步读取，close() 之后不会误存
  const { comic, page, mode, zoom, scale, direction } = useReader.getState()
  if (!comic) return
  try {
    const updated = await window.api.updateProgress(comic.id, {
      lastReadPage: page,
      reader: { mode, zoom, zoomScale: scale, direction }
    })
    if (updated) useLibrary.getState().applyComicPatch(updated)
  } catch {
    /* 进度保存失败不打断阅读，下一次翻页会再试 */
  }
}

export const useReader = create<ReaderState>()((set, get) => ({
  active: false,
  opening: false,
  error: null,
  comic: null,
  pageCount: 0,
  page: 0,
  mode: 'single',
  zoom: 'fitWidth',
  scale: 1,
  direction: 'ltr',

  open: async (id, opts) => {
    set({ active: true, opening: true, error: null, comic: null, pageCount: 0 })
    const res = await window.api.openComic(id)
    if (!res.ok || !res.comic) {
      set({ opening: false, error: res.error ?? '打开失败' })
      return
    }
    const defaults = useSettings.getState().settings
    const prefs = res.comic.reader ?? {}
    const pageCount = res.pageCount ?? res.comic.pageCount
    const page = opts?.fromStart
      ? 0
      : Math.min(Math.max(0, res.comic.lastReadPage), Math.max(0, pageCount - 1))
    set({
      opening: false,
      error: null,
      comic: res.comic,
      pageCount,
      page,
      mode: prefs.mode ?? defaults.defaultMode,
      zoom: prefs.zoom ?? defaults.defaultZoom,
      scale: prefs.zoomScale ?? 1,
      direction: prefs.direction ?? defaults.readingDirection
    })
    useLibrary.getState().applyComicPatch(res.comic)
    if (opts?.fromStart) schedulePersist()
  },

  close: () => {
    void flushPersist() // 状态读取是同步的，先存后清安全
    clearPageCache()
    set({ active: false, opening: false, error: null, comic: null, pageCount: 0, page: 0 })
  },

  setPage: (n) => {
    const { pageCount, page } = get()
    const clamped = Math.min(Math.max(0, Math.round(n)), Math.max(0, pageCount - 1))
    if (clamped === page) return
    set({ page: clamped })
    schedulePersist()
  },

  next: () => {
    const { page, mode } = get()
    get().setPage(page + (mode === 'double' ? 2 : 1))
  },

  prev: () => {
    const { page, mode } = get()
    get().setPage(page - (mode === 'double' ? 2 : 1))
  },

  setMode: (mode) => {
    if (mode === get().mode) return
    set({ mode })
    schedulePersist()
  },

  setZoom: (zoom) => {
    if (zoom === get().zoom) return
    set({ zoom, scale: 1 }) // 切换缩放基准时重置倍率，避免叠加出意外尺寸
    schedulePersist()
  },

  setScale: (scale) => {
    const clamped = clampZoomScale(scale)
    if (clamped === get().scale) return
    set({ scale: clamped })
    schedulePersist()
  },

  setDirection: (direction) => {
    if (direction === get().direction) return
    set({ direction })
    schedulePersist()
  }
}))
