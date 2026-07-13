import { memo, useCallback, useState, type ReactNode } from 'react'
import type { Comic } from '@shared/types'
import { Icon } from '@/components/common/Icon'
import { useClickOutside } from '@/hooks/useClickOutside'
import { useLibrary } from '@/store/library'
import { useReader } from '@/store/reader'
import { coverUrl } from '@/utils/comicUrl'
import { readPercent, relativeTime } from '@/utils/format'

interface ComicCardProps {
  comic: Comic
  missing: boolean
  onDelete: (comic: Comic) => void
}

/** 书架卡片。memo 化：虚拟滚动时只有进出视口和数据变化的卡片会重渲染。 */
function ComicCard({ comic, missing, onDelete }: ComicCardProps): ReactNode {
  const open = useReader((s) => s.open)
  const [menuOpen, setMenuOpen] = useState(false)
  const [coverFailed, setCoverFailed] = useState(false)
  const closeMenu = useCallback(() => setMenuOpen(false), [])
  const menuRef = useClickOutside<HTMLDivElement>(closeMenu)

  const percent = readPercent(comic.lastReadAt, comic.lastReadPage, comic.pageCount)
  const finished = percent >= 100
  const hasCover = comic.coverFile && !coverFailed

  return (
    <div
      className="card"
      onClick={() => void open(comic.id)}
      onContextMenu={(e) => {
        e.preventDefault()
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

        <div className="card-menu" ref={menuRef} onClick={(e) => e.stopPropagation()}>
          <button
            className="icon-btn card-menu-btn"
            title="更多操作"
            onClick={() => setMenuOpen((v) => !v)}
          >
            <Icon name="more" size={16} />
          </button>
          {menuOpen && (
            <div className="dropdown-menu" onContextMenu={(e) => e.stopPropagation()}>
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
            </div>
          )}
        </div>

        {comic.lastReadAt !== null && (
          <div className="card-progress">
            <div className="card-progress-fill" style={{ width: `${percent}%` }} />
          </div>
        )}
      </div>

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
