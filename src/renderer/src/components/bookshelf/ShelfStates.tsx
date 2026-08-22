import type { ReactNode } from 'react'
import { Icon } from '@/components/common/Icon'
import { Spinner } from '@/components/common/Feedback'
import { useLibrary } from '@/store/library'
import { basename } from '@/utils/format'

/** 书架为空 */
export function EmptyShelf(): ReactNode {
  const importFrom = useLibrary((s) => s.importFrom)
  return (
    <div className="state-pane">
      <div className="state-icon">
        <Icon name="book" size={44} />
      </div>
      <h2>书架还是空的</h2>
      <p>导入本地漫画文件夹或 ZIP / CBZ / RAR / CBR 压缩包开始阅读，也可以直接把它们拖进窗口。</p>
      <div className="state-actions">
        <button className="btn btn-primary" onClick={() => void importFrom('folder')}>
          <Icon name="folder" size={15} />
          导入文件夹
        </button>
        <button className="btn" onClick={() => void importFrom('archive')}>
          <Icon name="archive" size={15} />
          导入压缩包
        </button>
      </div>
    </div>
  )
}

/** 搜索 / 分类筛选无结果 */
export function NoResults({
  query,
  categoryLabel,
  uncategorized = false
}: {
  query: string
  categoryLabel?: string | null
  /** 当前筛选是否为「未分类」哨兵（用户可以创建同名真实分类，不能靠名称区分） */
  uncategorized?: boolean
}): ReactNode {
  // 没有搜索词时说明是分类筛选出的空结果，换成分类文案
  if (query === '' && (uncategorized || categoryLabel)) {
    return (
      <div className="state-pane">
        <div className="state-icon">
          <Icon name="tag" size={40} />
        </div>
        <h2>{uncategorized ? '没有未分类的漫画' : `「${categoryLabel}」分类下还没有漫画`}</h2>
        <p>
          {uncategorized ? '每本漫画都已加入分类。' : '在卡片菜单中选择「设置分类…」即可加入。'}
        </p>
      </div>
    )
  }
  return (
    <div className="state-pane">
      <div className="state-icon">
        <Icon name="search" size={40} />
      </div>
      <h2>没有找到「{query}」</h2>
      <p>换个关键词试试。</p>
    </div>
  )
}

/** 书架加载骨架屏 */
export function ShelfSkeleton(): ReactNode {
  return (
    <div className="grid">
      {Array.from({ length: 12 }, (_, i) => (
        <div key={i} className="card skeleton">
          <div className="card-cover" />
          <div className="card-info">
            <div className="sk-line" />
            <div className="sk-line short" />
          </div>
        </div>
      ))}
    </div>
  )
}

/** 导入 / 批量重新扫描进行中的悬浮提示 */
export function ImportingToast(): ReactNode {
  const importing = useLibrary((s) => s.importing)
  if (!importing.active) return null
  return (
    <div className="importing-toast">
      <Spinner size={16} />
      <div className="importing-text">
        {importing.total > 0 ? (
          <>
            <span>
              正在{importing.label} {importing.current} / {importing.total}
            </span>
            <span className="importing-path">{basename(importing.path)}</span>
          </>
        ) : (
          <span>正在{importing.label}…</span>
        )}
      </div>
    </div>
  )
}

/** 拖拽悬停遮罩 */
export function DropOverlay(): ReactNode {
  return (
    <div className="drop-overlay">
      <div className="drop-box">
        <Icon name="plus" size={30} />
        <span>松开以导入漫画</span>
      </div>
    </div>
  )
}
