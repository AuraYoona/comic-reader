import { create } from 'zustand'
import type {
  Category,
  CategoryPatch,
  Comic,
  ImportResult,
  RestoreMode,
  SortKey
} from '@shared/types'
import type { ImportKind, ImportProgress } from '@shared/api'
import { enqueueCoverThumbnails, forgetCoverAttempt } from '@/lib/coverThumbs'
import { applyTheme, useSettings } from './settings'
import { useUi } from './ui'

/** 「未分类」筛选的哨兵 id；真实分类 id 是 UUID，不会撞上 */
export const UNCATEGORIZED_ID = '@uncategorized'

interface BusyState {
  active: boolean
  /** 进度提示的动词，如「导入」「重新扫描」 */
  label: string
  current: number
  total: number
  path: string
}

const IDLE_BUSY: BusyState = { active: false, label: '导入', current: 0, total: 0, path: '' }
const VERIFY_THROTTLE_MS = 8000
let lastVerifyAt = 0

interface LibraryState {
  comics: Comic[]
  loading: boolean
  importing: BusyState
  query: string
  sortKey: SortKey
  /** 来源文件已丢失的漫画 id */
  missingIds: Set<string>
  /** 全部分类（「自定义分类」扩展功能，按创建顺序） */
  categories: Category[]
  /** 分类筛选：null = 全部，UNCATEGORIZED_ID = 未分类；与 query 一样只存在于内存 */
  activeCategoryId: string | null
  /** 多选中的漫画 id；非空即进入选择模式 */
  selectedIds: Set<string>
  /** Shift 连选的锚点 */
  anchorId: string | null

  load: () => Promise<void>
  setQuery: (q: string) => void
  setSortKey: (k: SortKey) => void
  importFrom: (kind: ImportKind) => Promise<void>
  importDropped: (paths: string[]) => Promise<void>
  setImportProgress: (p: ImportProgress) => void
  remove: (id: string) => Promise<void>
  /** 批量移除 */
  removeMany: (ids: string[]) => Promise<void>
  /** 重命名书架标题；失败时提示并返回 false，调用方可保留编辑态 */
  rename: (id: string, title: string) => Promise<boolean>
  /** 批量检查来源是否存在（节流，窗口聚焦/加载后调用） */
  verify: (force?: boolean) => Promise<void>
  /** 重新扫描单本：刷新页数并重新生成封面 */
  rescan: (id: string) => Promise<void>
  /** 批量重新扫描 */
  rescanMany: (ids: string[]) => Promise<void>
  /** 整库搬盘后重新绑定来源路径；ids 为空表示处理全部来源丢失的记录 */
  relocate: (ids: string[]) => Promise<void>
  /** 扫描已记录的库根目录，自动上架新增漫画 */
  scanRoots: (opts?: { silent?: boolean }) => Promise<void>
  /** 导出数据与封面 */
  backup: () => Promise<void>
  /** 从备份恢复；replace 会整库覆盖 */
  restore: (mode: RestoreMode) => Promise<boolean>
  /** 用主进程返回的最新记录替换本地条目（进度更新后书架立即反映） */
  applyComicPatch: (comic: Comic) => void
  setActiveCategory: (id: string | null) => void
  /** 创建成功返回新分类，失败（重名等）提示错误并返回 null */
  createCategory: (name: string, color?: string) => Promise<Category | null>
  /** 修改成功返回 true；失败（重名等）提示错误并返回 false，调用方可保留编辑态 */
  updateCategory: (id: string, patch: CategoryPatch) => Promise<boolean>
  /** 删除分类只解除漫画与它的关联，不影响漫画本身 */
  deleteCategory: (id: string) => Promise<void>
  /** 把漫画加入/移出一个分类（方向由主进程按当前归属判定，快速连点不会互相覆盖） */
  toggleComicCategory: (comicId: string, categoryId: string) => Promise<void>
  /** 批量设置分类：add=true 全部加入，false 全部移出 */
  setCategoryMany: (ids: string[], categoryId: string, add: boolean) => Promise<void>

  toggleSelect: (id: string) => void
  selectRange: (orderedIds: string[], id: string) => void
  selectAll: (ids: string[]) => void
  clearSelection: () => void
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

export const useLibrary = create<LibraryState>()((set, get) => {
  /** 新到手的记录统一在这里排封面压缩队列 */
  const queueCovers = (comics: Comic[]): void => {
    enqueueCoverThumbnails(comics, (comic) => get().applyComicPatch(comic))
  }

  /** 批量导入的公共收尾：并入书架、排封面、提示结果 */
  const absorbImport = (results: ImportResult[]): Comic[] => {
    const added = results
      .filter((r) => r.status === 'imported' && r.comic)
      .map((r) => r.comic as Comic)
    if (added.length > 0) {
      set((s) => ({ comics: [...s.comics, ...added] }))
      queueCovers(added)
    }
    return added
  }

  const dropFromSelection = (ids: string[]): void => {
    const gone = new Set(ids)
    set((s) => {
      if (s.selectedIds.size === 0) return {}
      const selectedIds = new Set([...s.selectedIds].filter((id) => !gone.has(id)))
      return { selectedIds, anchorId: gone.has(s.anchorId ?? '') ? null : s.anchorId }
    })
  }

  return {
    comics: [],
    loading: true,
    importing: IDLE_BUSY,
    query: '',
    sortKey: 'lastReadAt',
    missingIds: new Set<string>(),
    categories: [],
    activeCategoryId: null,
    selectedIds: new Set<string>(),
    anchorId: null,

    load: async () => {
      set({ loading: true })
      try {
        const [comics, categories] = await Promise.all([
          window.api.getLibrary(),
          window.api.listCategories()
        ])
        set({ comics, categories, loading: false })
        queueCovers(comics)
      } catch {
        set({ loading: false })
        useUi.getState().toast('读取书架数据失败', 'error')
      }
    },

    setQuery: (query) => set({ query }),
    setSortKey: (sortKey) => set({ sortKey }),

    importFrom: async (kind) => {
      if (get().importing.active) return
      set({ importing: { ...IDLE_BUSY, active: true } })
      try {
        const results = await window.api.importSelect(kind)
        absorbImport(results)
        summarizeImport(results)
      } catch {
        useUi.getState().toast('导入过程出现异常', 'error')
      } finally {
        set({ importing: IDLE_BUSY })
      }
    },

    importDropped: async (paths) => {
      if (paths.length === 0 || get().importing.active) return
      set({ importing: { ...IDLE_BUSY, active: true, total: paths.length } })
      try {
        const results = await window.api.importPaths(paths)
        absorbImport(results)
        summarizeImport(results)
      } catch {
        useUi.getState().toast('导入过程出现异常', 'error')
      } finally {
        set({ importing: IDLE_BUSY })
      }
    },

    setImportProgress: (p) =>
      set((s) =>
        s.importing.active
          ? { importing: { ...s.importing, current: p.current, total: p.total, path: p.path } }
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
        dropFromSelection([id])
        useUi.getState().toast('已从书架移除（原文件未删除）', 'success')
      } catch {
        useUi.getState().toast('移除失败', 'error')
      }
    },

    removeMany: async (ids) => {
      if (ids.length === 0) return
      try {
        const removed = await window.api.removeComics(ids)
        if (removed.length === 0) return
        const gone = new Set(removed)
        set((s) => {
          const missingIds = new Set([...s.missingIds].filter((id) => !gone.has(id)))
          return { comics: s.comics.filter((c) => !gone.has(c.id)), missingIds }
        })
        dropFromSelection(removed)
        useUi.getState().toast(`已移除 ${removed.length} 本（原文件未删除）`, 'success')
      } catch {
        useUi.getState().toast('批量移除失败', 'error')
      }
    },

    rename: async (id, title) => {
      try {
        const res = await window.api.renameComic(id, title)
        if (res.ok && res.comic) {
          get().applyComicPatch(res.comic)
          return true
        }
        useUi.getState().toast(res.error ?? '重命名失败', 'error')
        return false
      } catch {
        useUi.getState().toast('重命名失败', 'error')
        return false
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
          forgetCoverAttempt(id)
          queueCovers([res.comic])
          toast(`已重新扫描：共 ${res.pageCount ?? res.comic.pageCount} 页`, 'success')
        } else {
          toast(res.error ?? '重新扫描失败', 'error')
          void get().verify(true)
        }
      } catch {
        toast('重新扫描失败', 'error')
      }
    },

    rescanMany: async (ids) => {
      if (ids.length === 0 || get().importing.active) return
      const { toast } = useUi.getState()
      set({ importing: { ...IDLE_BUSY, active: true, label: '重新扫描', total: ids.length } })
      try {
        const res = await window.api.rescanComics(ids)
        for (const comic of res.updated) {
          get().applyComicPatch(comic)
          forgetCoverAttempt(comic.id)
        }
        queueCovers(res.updated)
        if (res.updated.length > 0) {
          const done = new Set(res.updated.map((c) => c.id))
          set((s) => ({ missingIds: new Set([...s.missingIds].filter((id) => !done.has(id))) }))
        }
        const parts = [`已重新扫描 ${res.updated.length} 本`]
        if (res.failed.length > 0) parts.push(`失败 ${res.failed.length} 本`)
        toast(parts.join('，'), res.failed.length > 0 ? 'error' : 'success')
        for (const item of res.failed.slice(0, 3)) toast(`${item.title}：${item.error}`, 'error')
        if (res.failed.length > 0) void get().verify(true)
      } catch {
        toast('批量重新扫描失败', 'error')
      } finally {
        set({ importing: IDLE_BUSY })
      }
    },

    relocate: async (ids) => {
      const { toast } = useUi.getState()
      try {
        const res = await window.api.relocateComics(ids)
        if (res.canceled) return
        if (res.error) {
          toast(res.error, 'error')
          return
        }
        for (const comic of res.relocated) get().applyComicPatch(comic)
        if (res.relocated.length > 0) {
          const done = new Set(res.relocated.map((c) => c.id))
          set((s) => ({ missingIds: new Set([...s.missingIds].filter((id) => !done.has(id))) }))
        }
        const parts = [`已重新定位 ${res.relocated.length} 本`]
        if (res.unmatched > 0) parts.push(`${res.unmatched} 本在新目录下没找到`)
        toast(parts.join('，'), res.relocated.length > 0 ? 'success' : 'error')
        void get().verify(true)
      } catch {
        toast('重新定位失败', 'error')
      }
    },

    scanRoots: async (opts) => {
      if (get().importing.active) return
      const { toast } = useUi.getState()
      set({ importing: { ...IDLE_BUSY, active: true } })
      try {
        const res = await window.api.scanLibraryRoots()
        if (res.added.length > 0) {
          set((s) => ({ comics: [...s.comics, ...res.added] }))
          queueCovers(res.added)
          toast(`库目录扫描：自动上架 ${res.added.length} 本`, 'success')
        } else if (!opts?.silent) {
          toast(res.roots === 0 ? '还没有设置漫画库根目录' : '库目录里没有新漫画', 'info')
        }
        for (const root of res.unreadable.slice(0, 2)) toast(`读不了根目录：${root}`, 'error')
      } catch {
        if (!opts?.silent) toast('扫描库目录失败', 'error')
      } finally {
        set({ importing: IDLE_BUSY })
      }
    },

    backup: async () => {
      const { toast } = useUi.getState()
      try {
        const res = await window.api.backupLibrary()
        if (res.canceled) return
        if (!res.ok) {
          toast(res.error ?? '导出失败', 'error')
          return
        }
        toast(`已导出 ${res.comics} 本、${res.covers} 张封面到 ${res.path}`, 'success')
      } catch {
        toast('导出失败', 'error')
      }
    },

    restore: async (mode) => {
      const { toast } = useUi.getState()
      try {
        const res = await window.api.restoreLibrary(mode)
        if (res.canceled) return false
        if (!res.ok) {
          toast(res.error ?? '恢复失败', 'error')
          return false
        }
        await get().load()
        // 覆盖恢复会把主进程里的全局设置一起换掉（主题、扩展开关、库根目录…），
        // 不重新拉一次的话界面还挂在旧设置上
        await useSettings.getState().load()
        applyTheme(useSettings.getState().settings.theme)
        void get().verify(true)
        toast(
          mode === 'replace'
            ? `已覆盖恢复 ${res.imported} 本`
            : `已合并 ${res.imported} 本，跳过 ${res.skipped} 本`,
          'success'
        )
        return true
      } catch {
        toast('恢复失败', 'error')
        return false
      }
    },

    applyComicPatch: (comic) =>
      set((s) => ({
        comics: s.comics.map((c) => (c.id === comic.id ? comic : c))
      })),

    setActiveCategory: (activeCategoryId) => set({ activeCategoryId }),

    createCategory: async (name, color) => {
      try {
        const res = await window.api.createCategory(name, color)
        if (res.ok && res.category) {
          const category = res.category
          set((s) => ({ categories: [...s.categories, category] }))
          return category
        }
        useUi.getState().toast(res.error ?? '创建分类失败', 'error')
        return null
      } catch {
        useUi.getState().toast('创建分类失败', 'error')
        return null
      }
    },

    updateCategory: async (id, patch) => {
      try {
        const res = await window.api.updateCategory(id, patch)
        if (res.ok && res.category) {
          const category = res.category
          set((s) => ({ categories: s.categories.map((c) => (c.id === id ? category : c)) }))
          return true
        }
        useUi.getState().toast(res.error ?? '修改分类失败', 'error')
        return false
      } catch {
        useUi.getState().toast('修改分类失败', 'error')
        return false
      }
    },

    deleteCategory: async (id) => {
      try {
        const ok = await window.api.deleteCategory(id)
        if (!ok) {
          useUi.getState().toast('删除分类失败', 'error')
          return
        }
        set((s) => ({
          categories: s.categories.filter((c) => c.id !== id),
          // 只给受影响的漫画换新对象，其余保持引用不变，memo 卡片不会重渲染
          comics: s.comics.map((c) =>
            c.categoryIds.includes(id)
              ? { ...c, categoryIds: c.categoryIds.filter((cid) => cid !== id) }
              : c
          ),
          activeCategoryId: s.activeCategoryId === id ? null : s.activeCategoryId
        }))
      } catch {
        useUi.getState().toast('删除分类失败', 'error')
      }
    },

    toggleComicCategory: async (comicId, categoryId) => {
      try {
        const comic = await window.api.toggleComicCategory(comicId, categoryId)
        if (comic) get().applyComicPatch(comic)
        else useUi.getState().toast('设置分类失败', 'error')
      } catch {
        useUi.getState().toast('设置分类失败', 'error')
      }
    },

    setCategoryMany: async (ids, categoryId, add) => {
      if (ids.length === 0) return
      try {
        const changed = await window.api.toggleComicCategoryMany(ids, categoryId, add)
        for (const comic of changed) get().applyComicPatch(comic)
        useUi
          .getState()
          .toast(
            add ? `已把 ${changed.length} 本加入分类` : `已把 ${changed.length} 本移出分类`,
            'success'
          )
      } catch {
        useUi.getState().toast('批量设置分类失败', 'error')
      }
    },

    toggleSelect: (id) =>
      set((s) => {
        const selectedIds = new Set(s.selectedIds)
        if (selectedIds.has(id)) selectedIds.delete(id)
        else selectedIds.add(id)
        return { selectedIds, anchorId: id }
      }),

    selectRange: (orderedIds, id) =>
      set((s) => {
        const anchor = s.anchorId
        const to = orderedIds.indexOf(id)
        const from = anchor ? orderedIds.indexOf(anchor) : -1
        if (to < 0 || from < 0) {
          const selectedIds = new Set(s.selectedIds)
          selectedIds.add(id)
          return { selectedIds, anchorId: id }
        }
        const [lo, hi] = from <= to ? [from, to] : [to, from]
        const selectedIds = new Set(s.selectedIds)
        for (let i = lo; i <= hi; i++) selectedIds.add(orderedIds[i])
        return { selectedIds } // 锚点保持不动，方便反复调整范围
      }),

    selectAll: (ids) => set({ selectedIds: new Set(ids), anchorId: ids[ids.length - 1] ?? null }),

    clearSelection: () => set({ selectedIds: new Set<string>(), anchorId: null })
  }
})
