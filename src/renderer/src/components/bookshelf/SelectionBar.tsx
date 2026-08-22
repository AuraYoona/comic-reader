import { useCallback, useRef, useState, type ReactNode } from 'react'
import DropdownMenu from '@/components/common/DropdownMenu'
import { Icon } from '@/components/common/Icon'
import { useLibrary } from '@/store/library'
import { useSettings } from '@/store/settings'

interface SelectionBarProps {
  /** 当前筛选结果的 id（「全选」只作用于看得见的部分） */
  visibleIds: string[]
  onRemove: () => void
}

/** 多选时浮在书架底部的批量操作条 */
export default function SelectionBar({ visibleIds, onRemove }: SelectionBarProps): ReactNode {
  const selectedIds = useLibrary((s) => s.selectedIds)
  const categories = useLibrary((s) => s.categories)
  const selectAll = useLibrary((s) => s.selectAll)
  const clearSelection = useLibrary((s) => s.clearSelection)
  const rescanMany = useLibrary((s) => s.rescanMany)
  const relocate = useLibrary((s) => s.relocate)
  const setCategoryMany = useLibrary((s) => s.setCategoryMany)
  const busy = useLibrary((s) => s.importing.active)
  const categoriesEnabled = useSettings((s) => s.settings.extensions.categories)

  const [catOpen, setCatOpen] = useState(false)
  const catBtnRef = useRef<HTMLButtonElement>(null)
  const closeCat = useCallback(() => setCatOpen(false), [])

  const count = selectedIds.size
  if (count === 0) return null
  const ids = [...selectedIds]
  const allSelected = visibleIds.length > 0 && visibleIds.every((id) => selectedIds.has(id))

  const applyCategory = (categoryId: string, add: boolean): void => {
    closeCat()
    void setCategoryMany(ids, categoryId, add)
  }

  return (
    <div className="selection-bar" role="toolbar" aria-label="批量操作">
      <span className="selection-count">已选 {count} 本</span>

      <button
        className="btn btn-sm btn-ghost"
        onClick={() => (allSelected ? clearSelection() : selectAll(visibleIds))}
      >
        <Icon name={allSelected ? 'square' : 'check-square'} size={14} />
        {allSelected ? '取消全选' : `全选（${visibleIds.length}）`}
      </button>

      <span className="selection-divider" />

      {categoriesEnabled && categories.length > 0 && (
        <>
          <button
            ref={catBtnRef}
            className="btn btn-sm btn-ghost"
            onClick={() => setCatOpen((v) => !v)}
          >
            <Icon name="tag" size={14} />
            分类
            <Icon name="chevron-down" size={12} />
          </button>
          <DropdownMenu open={catOpen} anchorRef={catBtnRef} align="left" onClose={closeCat}>
            <span className="dropdown-section">加入分类</span>
            {categories.map((c) => (
              <button key={`add-${c.id}`} onClick={() => applyCategory(c.id, true)}>
                <span className="cat-dot" style={{ background: c.color }} />
                {c.name}
              </button>
            ))}
            <span className="dropdown-section">移出分类</span>
            {categories.map((c) => (
              <button key={`del-${c.id}`} onClick={() => applyCategory(c.id, false)}>
                <span className="cat-dot" style={{ background: c.color }} />
                {c.name}
              </button>
            ))}
          </DropdownMenu>
        </>
      )}

      <button className="btn btn-sm btn-ghost" disabled={busy} onClick={() => void rescanMany(ids)}>
        <Icon name="refresh" size={14} />
        重新扫描
      </button>

      <button className="btn btn-sm btn-ghost" onClick={() => void relocate(ids)}>
        <Icon name="move" size={14} />
        重新定位来源…
      </button>

      <button className="btn btn-sm btn-ghost danger-text" onClick={onRemove}>
        <Icon name="trash" size={14} />
        移除…
      </button>

      <button className="icon-btn icon-btn-sm" title="退出多选 (Esc)" onClick={clearSelection}>
        <Icon name="close" size={14} />
      </button>
    </div>
  )
}
