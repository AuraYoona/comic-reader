import {
  useCallback,
  useEffect,
  useState,
  type ReactNode,
  type RefObject
} from 'react'
import type { SortKey } from '@shared/types'
import { Icon } from '@/components/common/Icon'
import { useClickOutside } from '@/hooks/useClickOutside'
import { resolvedThemeIsDark, useSettings } from '@/store/settings'
import { useLibrary } from '@/store/library'

const SORT_OPTIONS: { value: SortKey; label: string }[] = [
  { value: 'lastReadAt', label: '最近阅读' },
  { value: 'title', label: '名称' },
  { value: 'addedAt', label: '导入时间' }
]

const SEARCH_DEBOUNCE_MS = 150

interface TopBarProps {
  onOpenSettings: () => void
  searchInputRef: RefObject<HTMLInputElement>
}

export default function TopBar({ onOpenSettings, searchInputRef }: TopBarProps): ReactNode {
  const query = useLibrary((s) => s.query)
  const setQuery = useLibrary((s) => s.setQuery)
  const sortKey = useLibrary((s) => s.sortKey)
  const setSortKey = useLibrary((s) => s.setSortKey)
  const importFrom = useLibrary((s) => s.importFrom)
  const importing = useLibrary((s) => s.importing.active)
  const theme = useSettings((s) => s.settings.theme)
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
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query])

  const [importOpen, setImportOpen] = useState(false)
  const closeImport = useCallback(() => setImportOpen(false), [])
  const importRef = useClickOutside<HTMLDivElement>(closeImport)

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
        <label className="sort-box" title="排序方式">
          <span className="sort-label">排序</span>
          <select value={sortKey} onChange={(e) => setSortKey(e.target.value as SortKey)}>
            {SORT_OPTIONS.map((o) => (
              <option key={o.value} value={o.value}>
                {o.label}
              </option>
            ))}
          </select>
        </label>

        <div className="dropdown" ref={importRef}>
          <button
            className="btn btn-primary"
            disabled={importing}
            onClick={() => setImportOpen((v) => !v)}
          >
            <Icon name="plus" size={15} />
            导入
            <Icon name="chevron-down" size={13} />
          </button>
          {importOpen && (
            <div className="dropdown-menu">
              <button onClick={() => runImport('folder')}>
                <Icon name="folder" size={15} />
                导入文件夹…
              </button>
              <button onClick={() => runImport('archive')}>
                <Icon name="archive" size={15} />
                导入压缩包（ZIP / CBZ）…
              </button>
              <button onClick={() => runImport('batch')}>
                <Icon name="folder-open" size={15} />
                批量导入子文件夹…
              </button>
            </div>
          )}
        </div>

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
