import { create } from 'zustand'
import { isLastSpread, stepSpread, type SpreadContext } from '@shared/paging'
import {
  clampZoomScale,
  type Comic,
  type PageOffset,
  type ReadingDirection,
  type ReadingMode,
  type ZoomMode
} from '@shared/types'
import { clearCropCache } from '@/lib/autoCrop'
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
  /** 双页配对偏移：1 = 封面单独占屏 */
  pageOffset: PageOffset
  /** 自动裁白边 */
  autoCrop: boolean
  /** 已经加载并确认为横向跨页的页码 */
  widePages: Set<number>
  /** 书签页码，与主进程记录保持同步 */
  bookmarks: number[]
  /** 自动翻页进行中 */
  autoTurn: boolean
  /** 缩略图跳页条展开 */
  thumbStrip: boolean
  /** 已翻到最后一屏：显示提示，再翻一次直接返回书架 */
  endHint: boolean

  open: (id: string, opts?: { fromStart?: boolean }) => Promise<void>
  close: () => void
  setPage: (n: number) => void
  next: () => void
  prev: () => void
  setMode: (m: ReadingMode) => void
  setZoom: (z: ZoomMode) => void
  setScale: (s: number) => void
  setDirection: (d: ReadingDirection) => void
  setPageOffset: (o: PageOffset) => void
  togglePageOffset: () => void
  toggleAutoCrop: () => void
  /** 图片加载后回报是否为跨页图 */
  markWide: (index: number, wide: boolean) => void
  /** 增删当前页（或指定页）的书签 */
  toggleBookmark: (page?: number) => Promise<void>
  toggleAutoTurn: () => void
  stopAutoTurn: () => void
  toggleThumbStrip: () => void
  clearEndHint: () => void
}

const PERSIST_DEBOUNCE_MS = 900
const END_HINT_MS = 2600

let persistTimer: number | null = null
let endHintTimer: number | null = null

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
  const { comic, page, mode, zoom, scale, direction, pageOffset, autoCrop } = useReader.getState()
  if (!comic) return
  try {
    const updated = await window.api.updateProgress(comic.id, {
      lastReadPage: page,
      reader: { mode, zoom, zoomScale: scale, direction, pageOffset, autoCrop }
    })
    if (updated) useLibrary.getState().applyComicPatch(updated)
  } catch {
    /* 进度保存失败不打断阅读，下一次翻页会再试 */
  }
}

/** 双页分屏上下文：跨页独占由全局设置控制 */
function spreadContext(
  s: Pick<ReaderState, 'pageCount' | 'pageOffset' | 'widePages'>
): SpreadContext {
  const { widePageSpread } = useSettings.getState().settings
  return {
    pageCount: s.pageCount,
    offset: s.pageOffset,
    isWide: widePageSpread ? (i) => s.widePages.has(i) : undefined
  }
}

export const useReader = create<ReaderState>()((set, get) => {
  /** 翻到尽头：先提示，短时间内再翻一次就返回书架 */
  const hitEnd = (): void => {
    if (get().endHint) {
      get().close()
      return
    }
    set({ endHint: true, autoTurn: false })
    if (endHintTimer !== null) window.clearTimeout(endHintTimer)
    endHintTimer = window.setTimeout(() => {
      endHintTimer = null
      if (useReader.getState().endHint) set({ endHint: false })
    }, END_HINT_MS)
  }

  return {
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
    pageOffset: 1,
    autoCrop: false,
    widePages: new Set<number>(),
    bookmarks: [],
    autoTurn: false,
    thumbStrip: false,
    endHint: false,

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
      clearCropCache()
      set({
        opening: false,
        error: null,
        comic: res.comic,
        pageCount,
        page,
        mode: prefs.mode ?? defaults.defaultMode,
        zoom: prefs.zoom ?? defaults.defaultZoom,
        scale: prefs.zoomScale ?? 1,
        direction: prefs.direction ?? defaults.readingDirection,
        pageOffset: prefs.pageOffset ?? (defaults.doubleCoverSingle ? 1 : 0),
        autoCrop: prefs.autoCrop ?? defaults.autoCrop,
        widePages: new Set<number>(),
        bookmarks: res.comic.bookmarks,
        autoTurn: false,
        thumbStrip: false,
        endHint: false
      })
      useLibrary.getState().applyComicPatch(res.comic)
      if (opts?.fromStart) schedulePersist()
    },

    close: () => {
      void flushPersist() // 状态读取是同步的，先存后清安全
      clearPageCache()
      clearCropCache()
      if (endHintTimer !== null) {
        window.clearTimeout(endHintTimer)
        endHintTimer = null
      }
      set({
        active: false,
        opening: false,
        error: null,
        comic: null,
        pageCount: 0,
        page: 0,
        widePages: new Set<number>(),
        bookmarks: [],
        autoTurn: false,
        thumbStrip: false,
        endHint: false
      })
    },

    setPage: (n) => {
      const { pageCount, page, endHint } = get()
      const clamped = Math.min(Math.max(0, Math.round(n)), Math.max(0, pageCount - 1))
      if (clamped === page) return
      set(endHint ? { page: clamped, endHint: false } : { page: clamped })
      schedulePersist()
    },

    next: () => {
      const s = get()
      if (s.pageCount === 0) return
      if (s.mode === 'double') {
        const ctx = spreadContext(s)
        if (isLastSpread(s.page, ctx)) {
          hitEnd()
          return
        }
        get().setPage(stepSpread(s.page, 1, ctx))
        return
      }
      if (s.page >= s.pageCount - 1) {
        hitEnd()
        return
      }
      get().setPage(s.page + 1)
    },

    prev: () => {
      const s = get()
      if (s.pageCount === 0) return
      if (s.mode === 'double') {
        get().setPage(stepSpread(s.page, -1, spreadContext(s)))
        return
      }
      get().setPage(s.page - 1)
    },

    setMode: (mode) => {
      if (mode === get().mode) return
      set({ mode, endHint: false })
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
    },

    setPageOffset: (pageOffset) => {
      if (pageOffset === get().pageOffset) return
      set({ pageOffset })
      schedulePersist()
    },

    togglePageOffset: () => get().setPageOffset(get().pageOffset === 1 ? 0 : 1),

    toggleAutoCrop: () => {
      set({ autoCrop: !get().autoCrop })
      schedulePersist()
    },

    markWide: (index, wide) => {
      const { widePages } = get()
      if (widePages.has(index) === wide) return
      const next = new Set(widePages)
      if (wide) next.add(index)
      else next.delete(index)
      set({ widePages: next })
    },

    toggleBookmark: async (page) => {
      const { comic } = get()
      if (!comic) return
      const target = page ?? get().page
      try {
        const updated = await window.api.toggleBookmark(comic.id, target)
        if (!updated) return
        set({ bookmarks: updated.bookmarks, comic: updated })
        useLibrary.getState().applyComicPatch(updated)
      } catch {
        /* 书签失败不打断阅读 */
      }
    },

    toggleAutoTurn: () => set({ autoTurn: !get().autoTurn, endHint: false }),

    stopAutoTurn: () => {
      if (get().autoTurn) set({ autoTurn: false })
    },

    toggleThumbStrip: () => set({ thumbStrip: !get().thumbStrip }),

    clearEndHint: () => {
      if (get().endHint) set({ endHint: false })
    }
  }
})
