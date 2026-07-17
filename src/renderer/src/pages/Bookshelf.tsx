import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import type { CardSize, Comic } from '@shared/types'
import CategoryAssignModal from '@/components/bookshelf/CategoryAssignModal'
import CategoryManagerModal from '@/components/bookshelf/CategoryManagerModal'
import ComicCard from '@/components/bookshelf/ComicCard'
import SettingsModal from '@/components/bookshelf/SettingsModal'
import TopBar from '@/components/bookshelf/TopBar'
import {
  DropOverlay,
  EmptyShelf,
  ImportingToast,
  NoResults,
  ShelfSkeleton
} from '@/components/bookshelf/ShelfStates'
import Modal from '@/components/common/Modal'
import { useVirtualGrid } from '@/hooks/useVirtualGrid'
import { UNCATEGORIZED_ID, useLibrary } from '@/store/library'
import { useReader } from '@/store/reader'
import { useSettings } from '@/store/settings'

const titleCollator = new Intl.Collator(['zh', 'en'], { numeric: true, sensitivity: 'base' })

/** 卡片大小 → 最小宽度（决定列数） */
const CARD_MIN_WIDTH: Record<CardSize, number> = { small: 128, medium: 160, large: 200 }
const GRID_GAP = 16
/** 封面下信息区高度（标题固定两行 + 元信息行），与 CSS 对应 */
const CARD_INFO_HEIGHT = 66

export default function Bookshelf(): ReactNode {
  const comics = useLibrary((s) => s.comics)
  const loading = useLibrary((s) => s.loading)
  const query = useLibrary((s) => s.query)
  const sortKey = useLibrary((s) => s.sortKey)
  const missingIds = useLibrary((s) => s.missingIds)
  const categories = useLibrary((s) => s.categories)
  const activeCategoryId = useLibrary((s) => s.activeCategoryId)
  const remove = useLibrary((s) => s.remove)
  const importDropped = useLibrary((s) => s.importDropped)
  const cardSize = useSettings((s) => s.settings.cardSize)
  const categoriesEnabled = useSettings((s) => s.settings.extensions.categories)

  const [settingsOpen, setSettingsOpen] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<Comic | null>(null)
  const [categoryTarget, setCategoryTarget] = useState<Comic | null>(null)
  const [categoryManagerOpen, setCategoryManagerOpen] = useState(false)
  const [dragOver, setDragOver] = useState(false)
  const dragDepth = useRef(0)
  const searchInputRef = useRef<HTMLInputElement>(null)

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase()
    // 扩展关闭时忽略残留的分类筛选；filter 总是产出新数组，原地 sort 不会动到 store
    const cat = categoriesEnabled ? activeCategoryId : null
    const filtered = comics.filter((c) => {
      if (cat === UNCATEGORIZED_ID) {
        if (c.categoryIds.length > 0) return false
      } else if (cat !== null && !c.categoryIds.includes(cat)) {
        return false
      }
      return q === '' || c.title.toLowerCase().includes(q)
    })
    switch (sortKey) {
      case 'title':
        return filtered.sort((a, b) => titleCollator.compare(a.title, b.title))
      case 'addedAt':
        return filtered.sort((a, b) => b.addedAt - a.addedAt)
      case 'lastReadAt':
      default:
        // 读过的按时间倒序排前面，没读过的按导入时间排后面
        return filtered.sort(
          (a, b) => (b.lastReadAt ?? 0) - (a.lastReadAt ?? 0) || b.addedAt - a.addedAt
        )
    }
  }, [comics, query, sortKey, categoriesEnabled, activeCategoryId])

  const { containerRef, onScroll, totalHeight, items } = useVirtualGrid({
    count: visible.length,
    minItemWidth: CARD_MIN_WIDTH[cardSize],
    gap: GRID_GAP,
    extraHeight: CARD_INFO_HEIGHT
  })

  // 分类弹窗跟随 store 里的最新记录：勾选后立即刷新，漫画被移除时自动关闭
  const liveCategoryTarget = categoryTarget
    ? (comics.find((c) => c.id === categoryTarget.id) ?? null)
    : null

  // 空结果文案用：当前分类筛选的名称（未分类 / 分类名）
  const activeCategoryLabel = useMemo(() => {
    if (!categoriesEnabled || activeCategoryId === null) return null
    if (activeCategoryId === UNCATEGORIZED_ID) return '未分类'
    return categories.find((c) => c.id === activeCategoryId)?.name ?? null
  }, [categoriesEnabled, activeCategoryId, categories])

  // 切换分类筛选后回到顶部
  useEffect(() => {
    if (containerRef.current) containerRef.current.scrollTop = 0
  }, [activeCategoryId, categoriesEnabled, containerRef])

  // 来源存在性校验：加载后 + 窗口重新聚焦时（节流）
  useEffect(() => {
    if (!loading) void useLibrary.getState().verify(true)
  }, [loading])
  useEffect(() => {
    const onFocus = (): void => {
      if (!useReader.getState().active) void useLibrary.getState().verify()
    }
    window.addEventListener('focus', onFocus)
    return () => window.removeEventListener('focus', onFocus)
  }, [])

  // Ctrl+F 聚焦搜索（阅读器打开时不响应）
  useEffect(() => {
    const onKey = (e: KeyboardEvent): void => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'f') {
        if (useReader.getState().active) return
        e.preventDefault()
        searchInputRef.current?.focus()
        searchInputRef.current?.select()
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  // 拖拽导入：文件夹 / zip / cbz（阅读器打开时忽略）
  useEffect(() => {
    const readerActive = (): boolean => useReader.getState().active
    const onDragEnter = (e: DragEvent): void => {
      e.preventDefault()
      if (readerActive()) return
      if (e.dataTransfer?.types.includes('Files')) {
        dragDepth.current++
        setDragOver(true)
      }
    }
    const onDragOver = (e: DragEvent): void => e.preventDefault()
    const onDragLeave = (e: DragEvent): void => {
      e.preventDefault()
      if (--dragDepth.current <= 0) {
        dragDepth.current = 0
        setDragOver(false)
      }
    }
    const onDrop = (e: DragEvent): void => {
      e.preventDefault()
      dragDepth.current = 0
      setDragOver(false)
      if (readerActive()) return
      const files = Array.from(e.dataTransfer?.files ?? [])
      const paths = files.map((f) => window.api.pathForFile(f)).filter(Boolean)
      if (paths.length > 0) void importDropped(paths)
    }
    window.addEventListener('dragenter', onDragEnter)
    window.addEventListener('dragover', onDragOver)
    window.addEventListener('dragleave', onDragLeave)
    window.addEventListener('drop', onDrop)
    return () => {
      window.removeEventListener('dragenter', onDragEnter)
      window.removeEventListener('dragover', onDragOver)
      window.removeEventListener('dragleave', onDragLeave)
      window.removeEventListener('drop', onDrop)
    }
  }, [importDropped])

  return (
    <div className="shelf">
      <TopBar
        onOpenSettings={() => setSettingsOpen(true)}
        onOpenCategoryManager={() => setCategoryManagerOpen(true)}
        searchInputRef={searchInputRef}
      />

      <main className="shelf-body" ref={containerRef} onScroll={onScroll}>
        {loading ? (
          <ShelfSkeleton />
        ) : comics.length === 0 ? (
          <EmptyShelf />
        ) : visible.length === 0 ? (
          <NoResults
            query={query.trim()}
            categoryLabel={activeCategoryLabel}
            uncategorized={categoriesEnabled && activeCategoryId === UNCATEGORIZED_ID}
          />
        ) : (
          <div className="vgrid" style={{ height: totalHeight }}>
            {items.map(({ index, style }) => {
              const comic = visible[index]
              if (!comic) return null
              return (
                <div key={comic.id} className="vgrid-item" style={style}>
                  <ComicCard
                    comic={comic}
                    missing={missingIds.has(comic.id)}
                    onDelete={setDeleteTarget}
                    onSetCategories={setCategoryTarget}
                  />
                </div>
              )
            })}
          </div>
        )}
      </main>

      <ImportingToast />
      {dragOver && <DropOverlay />}
      {settingsOpen && <SettingsModal onClose={() => setSettingsOpen(false)} />}

      {liveCategoryTarget && (
        <CategoryAssignModal
          comic={liveCategoryTarget}
          onClose={() => setCategoryTarget(null)}
          onOpenManager={() => {
            // 先关掉本弹窗再开管理弹窗：叠放的弹窗会被一次 Esc 全部关闭
            setCategoryTarget(null)
            setCategoryManagerOpen(true)
          }}
        />
      )}
      {categoryManagerOpen && (
        <CategoryManagerModal onClose={() => setCategoryManagerOpen(false)} />
      )}

      {deleteTarget && (
        <Modal title="从书架移除" onClose={() => setDeleteTarget(null)} width={440}>
          <p className="confirm-text">
            将从书架移除《{deleteTarget.title}》。
            <br />
            <strong>原始文件不会被删除</strong>，之后可以重新导入。
          </p>
          <div className="modal-actions">
            <button className="btn" onClick={() => setDeleteTarget(null)}>
              取消
            </button>
            <button
              className="btn btn-danger"
              onClick={() => {
                void remove(deleteTarget.id)
                setDeleteTarget(null)
              }}
            >
              移除
            </button>
          </div>
        </Modal>
      )}
    </div>
  )
}
