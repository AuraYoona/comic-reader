import { useCallback, useEffect, useRef, useState, type ReactNode, type RefObject } from 'react'
import type { SortKey } from '@shared/types'
import DropdownMenu from '@/components/common/DropdownMenu'
import Select from '@/components/common/Select'
import { Icon } from '@/components/common/Icon'
import { resolvedThemeIsDark, useSettings } from '@/store/settings'
import { UNCATEGORIZED_ID, useLibrary } from '@/store/library'

const SORT_OPTIONS: { value: SortKey; label: string }[] = [
  { value: 'lastReadAt', label: '最近阅读' },
  { value: 'title', label: '名称' },
  { value: 'addedAt', label: '导入时间' }
]

/** 分类筛选里代表“全部”的哨兵值（分类 id 不会是空串） */
const ALL_CATEGORIES = ''

const SEARCH_DEBOUNCE_MS = 150

interface TopBarProps {
  onOpenSettings: () => void
  onOpenCategoryManager: () => void
  searchInputRef: RefObject<HTMLInputElement>
}

export default function TopBar({
  onOpenSettings,
  onOpenCategoryManager,
  searchInputRef
}: TopBarProps): ReactNode {
  const query = useLibrary((s) => s.query)
  const setQuery = useLibrary((s) => s.setQuery)
  const sortKey = useLibrary((s) => s.sortKey)
  const setSortKey = useLibrary((s) => s.setSortKey)
  const categories = useLibrary((s) => s.categories)
  const activeCategoryId = useLibrary((s) => s.activeCategoryId)
  const setActiveCategory = useLibrary((s) => s.setActiveCategory)
  const importFrom = useLibrary((s) => s.importFrom)
  const importing = useLibrary((s) => s.importing.active)
  const theme = useSettings((s) => s.settings.theme)
  const categoriesEnabled = useSettings((s) => s.settings.extensions.categories)
  const updateSettings = useSettings((s) => s.update)

  // 输入即时显示、过滤防抖：几千本时打字不卡
  const [text, setText] = useState(query)
  useEffect(() => {
    const t = window.setTimeout(() => setQuery(text), SEARCH_DEBOUNCE_MS)
    return () => window.clearTimeout(t)
  }, [text, setQuery])
  // 外部清空（例如“清除搜索”按钮）时同步回输入框
  useEffect(() => {
    setText(query)
  }, [query])

  const [importOpen, setImportOpen] = useState(false)
  const importBtnRef = useRef<HTMLButtonElement>(null)
  const closeImport = useCallback(() => setImportOpen(false), [])

  const isDark = resolvedThemeIsDark(theme)

  const runImport = (kind: 'folder' | 'archive' | 'batch'): void => {
    closeImport()
    void importFrom(kind)
  }

  return (
    <header className="topbar">
      <div className="topbar-brand">
        <Icon name="book" size={20} />
        <span>漫画书架</span>
      </div>

      <div className="topbar-search">
        <Icon name="search" size={15} />
        <input
          ref={searchInputRef}
          type="text"
          placeholder="搜索漫画…  (Ctrl+F)"
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Escape' && text) {
              e.stopPropagation()
              setText('')
              setQuery('')
            }
          }}
          spellCheck={false}
        />
        {text && (
          <button
            className="icon-btn icon-btn-sm"
            onClick={() => {
              setText('')
              setQuery('')
            }}
            title="清空"
          >
            <Icon name="close" size={13} />
          </button>
        )}
      </div>

      <div className="topbar-actions">
        {categoriesEnabled && (
          <>
            <div className="sort-box" title="按分类筛选">
              <span className="sort-label">分类</span>
              <Select
                ariaLabel="按分类筛选"
                value={activeCategoryId ?? ALL_CATEGORIES}
                options={[
                  { value: ALL_CATEGORIES, label: '全部' },
                  { value: UNCATEGORIZED_ID, label: '未分类' },
                  ...categories.map((c) => ({ value: c.id, label: c.name, dot: c.color }))
                ]}
                onChange={(v) => setActiveCategory(v === ALL_CATEGORIES ? null : v)}
              />
            </div>
            <button className="icon-btn" title="管理分类" onClick={onOpenCategoryManager}>
              <Icon name="tag" size={17} />
            </button>
          </>
        )}

        <div className="sort-box" title="排序方式">
          <span className="sort-label">排序</span>
          <Select
            ariaLabel="排序方式"
            value={sortKey}
            options={SORT_OPTIONS}
            onChange={setSortKey}
          />
        </div>

        <button
          ref={importBtnRef}
          className="btn btn-primary"
          disabled={importing}
          onClick={() => setImportOpen((v) => !v)}
        >
          <Icon name="plus" size={15} />
          导入
          <Icon name="chevron-down" size={13} />
        </button>
        <DropdownMenu
          open={importOpen}
          anchorRef={importBtnRef}
          align="right"
          onClose={closeImport}
        >
          <button onClick={() => runImport('folder')}>
            <Icon name="folder" size={15} />
            导入文件夹…
          </button>
          <button onClick={() => runImport('archive')}>
            <Icon name="archive" size={15} />
            导入压缩包（ZIP / CBZ / RAR / CBR）…
          </button>
          <button onClick={() => runImport('batch')}>
            <Icon name="folder-open" size={15} />
            批量导入子文件夹…
          </button>
        </DropdownMenu>

        <button
          className="icon-btn"
          title={isDark ? '切换到浅色模式' : '切换到深色模式'}
          onClick={() => void updateSettings({ theme: isDark ? 'light' : 'dark' })}
        >
          <Icon name={isDark ? 'sun' : 'moon'} size={17} />
        </button>

        <button className="icon-btn" title="设置" onClick={onOpenSettings}>
          <Icon name="settings" size={17} />
        </button>
      </div>
    </header>
  )
}
