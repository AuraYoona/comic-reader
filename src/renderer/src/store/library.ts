import { create } from 'zustand'
import type { Comic, ImportResult, SortKey } from '@shared/types'
import type { ImportKind, ImportProgress } from '@shared/api'
import { useUi } from './ui'

interface ImportingState {
  active: boolean
  current: number
  total: number
  path: string
}

const IDLE_IMPORT: ImportingState = { active: false, current: 0, total: 0, path: '' }
const VERIFY_THROTTLE_MS = 8000
let lastVerifyAt = 0

interface LibraryState {
  comics: Comic[]
  loading: boolean
  importing: ImportingState
  query: string
  sortKey: SortKey
  /** 来源文件已丢失的漫画 id */
  missingIds: Set<string>
  load: () => Promise<void>
  setQuery: (q: string) => void
  setSortKey: (k: SortKey) => void
  importFrom: (kind: ImportKind) => Promise<void>
  importDropped: (paths: string[]) => Promise<void>
  setImportProgress: (p: ImportProgress) => void
  remove: (id: string) => Promise<void>
  /** 批量检查来源是否存在（节流，窗口聚焦/加载后调用） */
  verify: (force?: boolean) => Promise<void>
  /** 重新扫描单本：刷新页数并重新生成封面 */
  rescan: (id: string) => Promise<void>
  /** 用主进程返回的最新记录替换本地条目（进度更新后书架立即反映） */
  applyComicPatch: (comic: Comic) => void
}

function summarizeImport(results: ImportResult[]): void {
  const { toast } = useUi.getState()
  if (results.length === 0) return
  const imported = results.filter((r) => r.status === 'imported').length
  const skipped = results.filter((r) => r.status === 'skipped').length
  const failedItems = results.filter((r) => r.status === 'failed')

  const parts: string[] = []
  if (imported > 0) parts.push(`成功导入 ${imported} 本`)
  if (skipped > 0) parts.push(`跳过 ${skipped} 本`)
  if (failedItems.length > 0) parts.push(`失败 ${failedItems.length} 本`)
  toast(parts.join('，'), failedItems.length > 0 ? 'error' : 'success')

  // 失败原因最多提示 3 条，避免刷屏
  for (const item of failedItems.slice(0, 3)) {
    const name = item.path.split(/[\\/]/).pop() ?? item.path
    toast(`${name}：${item.reason ?? '未知原因'}`, 'error')
  }
}

export const useLibrary = create<LibraryState>()((set, get) => ({
  comics: [],
  loading: true,
  importing: IDLE_IMPORT,
  query: '',
  sortKey: 'lastReadAt',
  missingIds: new Set<string>(),

  load: async () => {
    set({ loading: true })
    try {
      const comics = await window.api.getLibrary()
      set({ comics, loading: false })
    } catch {
      set({ loading: false })
      useUi.getState().toast('读取书架数据失败', 'error')
    }
  },

  setQuery: (query) => set({ query }),
  setSortKey: (sortKey) => set({ sortKey }),

  importFrom: async (kind) => {
    if (get().importing.active) return
    set({ importing: { ...IDLE_IMPORT, active: true } })
    try {
      const results = await window.api.importSelect(kind)
      const added = results
        .filter((r) => r.status === 'imported' && r.comic)
        .map((r) => r.comic as Comic)
      if (added.length > 0) set((s) => ({ comics: [...s.comics, ...added] }))
      summarizeImport(results)
    } catch {
      useUi.getState().toast('导入过程出现异常', 'error')
    } finally {
      set({ importing: IDLE_IMPORT })
    }
  },

  importDropped: async (paths) => {
    if (paths.length === 0 || get().importing.active) return
    set({ importing: { ...IDLE_IMPORT, active: true, total: paths.length } })
    try {
      const results = await window.api.importPaths(paths)
      const added = results
        .filter((r) => r.status === 'imported' && r.comic)
        .map((r) => r.comic as Comic)
      if (added.length > 0) set((s) => ({ comics: [...s.comics, ...added] }))
      summarizeImport(results)
    } catch {
      useUi.getState().toast('导入过程出现异常', 'error')
    } finally {
      set({ importing: IDLE_IMPORT })
    }
  },

  setImportProgress: (p) =>
    set((s) =>
      s.importing.active
        ? { importing: { active: true, current: p.current, total: p.total, path: p.path } }
        : {}
    ),

  remove: async (id) => {
    try {
      await window.api.removeComic(id)
      set((s) => {
        const missingIds = new Set(s.missingIds)
        missingIds.delete(id)
        return { comics: s.comics.filter((c) => c.id !== id), missingIds }
      })
      useUi.getState().toast('已从书架移除（原文件未删除）', 'success')
    } catch {
      useUi.getState().toast('移除失败', 'error')
    }
  },

  verify: async (force = false) => {
    const now = Date.now()
    if (!force && now - lastVerifyAt < VERIFY_THROTTLE_MS) return
    lastVerifyAt = now
    try {
      const checks = await window.api.verifyLibrary()
      set({ missingIds: new Set(checks.filter((c) => c.missing).map((c) => c.id)) })
    } catch {
      /* 校验失败不打扰用户，下次聚焦再试 */
    }
  },

  rescan: async (id) => {
    const { toast } = useUi.getState()
    try {
      const res = await window.api.rescanComic(id)
      if (res.ok && res.comic) {
        get().applyComicPatch(res.comic)
        set((s) => {
          const missingIds = new Set(s.missingIds)
          missingIds.delete(id)
          return { missingIds }
        })
        toast(`已重新扫描：共 ${res.pageCount ?? res.comic.pageCount} 页`, 'success')
      } else {
        toast(res.error ?? '重新扫描失败', 'error')
        void get().verify(true)
      }
    } catch {
      toast('重新扫描失败', 'error')
    }
  },

  applyComicPatch: (comic) =>
    set((s) => ({
      comics: s.comics.map((c) => (c.id === comic.id ? comic : c))
    }))
}))
