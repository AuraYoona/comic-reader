import { memo, useCallback, useRef, useState, type ReactNode } from 'react'
import type { Comic } from '@shared/types'
import DropdownMenu from '@/components/common/DropdownMenu'
import { Icon } from '@/components/common/Icon'
import { useLibrary } from '@/store/library'
import { useReader } from '@/store/reader'
import { useSettings } from '@/store/settings'
import { coverUrl } from '@/utils/comicUrl'
import { readPercent, relativeTime } from '@/utils/format'

interface ComicCardProps {
  comic: Comic
  missing: boolean
  onDelete: (comic: Comic) => void
  onSetCategories: (comic: Comic) => void
}

/** 书架卡片。memo 化：虚拟滚动时只有进出视口和数据变化的卡片会重渲染。 */
function ComicCard({ comic, missing, onDelete, onSetCategories }: ComicCardProps): ReactNode {
  const open = useReader((s) => s.open)
  const categoriesEnabled = useSettings((s) => s.settings.extensions.categories)
  const [menuOpen, setMenuOpen] = useState(false)
  const [menuPoint, setMenuPoint] = useState<{ x: number; y: number } | null>(null)
  const [coverFailed, setCoverFailed] = useState(false)
  const menuBtnRef = useRef<HTMLButtonElement>(null)
  const closeMenu = useCallback(() => {
    setMenuOpen(false)
    setMenuPoint(null)
  }, [])

  const percent = readPercent(comic.lastReadAt, comic.lastReadPage, comic.pageCount)
  const finished = percent >= 100
  const hasCover = comic.coverFile && !coverFailed

  return (
    <div
      className="card"
      onClick={() => void open(comic.id)}
      onContextMenu={(e) => {
        e.preventDefault()
        setMenuPoint({ x: e.clientX, y: e.clientY })
        setMenuOpen(true)
      }}
      title={comic.sourcePath}
    >
      <div className="card-cover">
        {hasCover ? (
          <img
            src={coverUrl(comic.id, comic.coverFile)}
            alt={comic.title}
            loading="lazy"
            decoding="async"
            draggable={false}
            onError={() => setCoverFailed(true)}
          />
        ) : (
          <div className="card-cover-fallback">
            <Icon name="book" size={34} />
          </div>
        )}

        <span className="card-pages">{comic.pageCount} 页</span>
        {missing && <span className="card-missing">来源丢失</span>}

        <div className="card-hover">
          <span className="card-open-hint">
            <Icon name="play" size={14} />
            {comic.lastReadAt && !finished ? '继续阅读' : '开始阅读'}
          </span>
        </div>

        <div className="card-menu" onClick={(e) => e.stopPropagation()}>
          <button
            ref={menuBtnRef}
            className={menuOpen ? 'icon-btn card-menu-btn open' : 'icon-btn card-menu-btn'}
            title="更多操作"
            onClick={() => {
              setMenuPoint(null)
              setMenuOpen((v) => !v)
            }}
          >
            <Icon name="more" size={16} />
          </button>
        </div>

        {comic.lastReadAt !== null && (
          <div className="card-progress">
            <div className="card-progress-fill" style={{ width: `${percent}%` }} />
          </div>
        )}
      </div>

      <DropdownMenu
        open={menuOpen}
        anchorRef={menuBtnRef}
        point={menuPoint}
        align={menuPoint ? 'left' : 'right'}
        onClose={closeMenu}
      >
        <button
          onClick={() => {
            closeMenu()
            void open(comic.id, { fromStart: true })
          }}
        >
          <Icon name="play" size={14} />
          从第一页开始
        </button>
        <button
          onClick={() => {
            closeMenu()
            void useLibrary.getState().rescan(comic.id)
          }}
        >
          <Icon name="refresh" size={14} />
          重新扫描（刷新页数和封面）
        </button>
        <button
          onClick={() => {
            closeMenu()
            void window.api.revealComic(comic.id)
          }}
        >
          <Icon name="folder-open" size={14} />
          打开所在位置
        </button>
        {categoriesEnabled && (
          <button
            onClick={() => {
              closeMenu()
              onSetCategories(comic)
            }}
          >
            <Icon name="tag" size={14} />
            设置分类…
          </button>
        )}
        <button
          className="danger"
          onClick={() => {
            closeMenu()
            onDelete(comic)
          }}
        >
          <Icon name="trash" size={14} />
          从书架移除…
        </button>
      </DropdownMenu>

      <div className="card-info">
        <div className="card-title" title={comic.title}>
          {comic.title}
        </div>
        <div className="card-meta">
          <span className={finished ? 'card-percent done' : 'card-percent'}>
            {comic.lastReadAt === null ? '未读' : finished ? '已读完' : `已读 ${percent}%`}
          </span>
          <span className="card-time">{relativeTime(comic.lastReadAt)}</span>
        </div>
      </div>
    </div>
  )
}

export default memo(ComicCard)
