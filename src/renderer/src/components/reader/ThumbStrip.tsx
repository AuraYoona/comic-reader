import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { useReader } from '@/store/reader'
import { useSettings } from '@/store/settings'
import { thumbUrl } from '@/utils/comicUrl'

const THUMB_W = 78
const THUMB_H = 108
const GAP = 6
const SLOT = THUMB_W + GAP
/** 视口左右各多挂几张，快速拖动时不至于露白 */
const OVERSCAN = 4

/**
 * 缩略图跳页条。
 *
 * 缩略图走 comic://thumb/，由主进程缩过再传，长篇也不会因为几十张原图而卡住。
 * 只给可视范围内的槽位挂 <img>，其余保留等宽占位。
 */
export default function ThumbStrip(): ReactNode {
  const comic = useReader((s) => s.comic)!
  const page = useReader((s) => s.page)
  const pageCount = useReader((s) => s.pageCount)
  const bookmarks = useReader((s) => s.bookmarks)
  const setPage = useReader((s) => s.setPage)
  const bookmarksEnabled = useSettings((s) => s.settings.extensions.bookmarks)

  const railRef = useRef<HTMLDivElement>(null)
  const [view, setView] = useState({ left: 0, width: 0 })
  const rafRef = useRef(0)

  const measure = useCallback(() => {
    const el = railRef.current
    if (!el) return
    setView({ left: el.scrollLeft, width: el.clientWidth })
  }, [])

  useEffect(() => {
    const el = railRef.current
    if (!el) return
    const ro = new ResizeObserver(measure)
    ro.observe(el)
    measure()
    return () => ro.disconnect()
  }, [measure])

  const onScroll = useCallback(() => {
    cancelAnimationFrame(rafRef.current)
    rafRef.current = requestAnimationFrame(measure)
  }, [measure])

  useEffect(() => () => cancelAnimationFrame(rafRef.current), [])

  // 当前页居中；页码由外部（键盘、滑块）改变时也跟着走
  useEffect(() => {
    const el = railRef.current
    if (!el || el.clientWidth === 0) return
    const target = page * SLOT + THUMB_W / 2 - el.clientWidth / 2
    el.scrollTo({ left: Math.max(0, target), behavior: 'smooth' })
  }, [page])

  const bookmarkSet = useMemo(() => new Set(bookmarks), [bookmarks])

  const [from, to] = useMemo(() => {
    if (view.width === 0) return [0, Math.min(pageCount, 24)]
    const start = Math.max(0, Math.floor(view.left / SLOT) - OVERSCAN)
    const end = Math.min(pageCount, Math.ceil((view.left + view.width) / SLOT) + OVERSCAN)
    return [start, end]
  }, [view, pageCount])

  return (
    <div className="thumb-strip" onClick={(e) => e.stopPropagation()}>
      <div className="thumb-rail" ref={railRef} onScroll={onScroll}>
        <div className="thumb-track" style={{ width: pageCount * SLOT - GAP }}>
          {Array.from({ length: to - from }, (_, k) => {
            const i = from + k
            const current = i === page
            return (
              <button
                key={i}
                className={current ? 'thumb-item current' : 'thumb-item'}
                style={{ left: i * SLOT, width: THUMB_W, height: THUMB_H }}
                title={`第 ${i + 1} 页`}
                onClick={() => setPage(i)}
              >
                <img
                  src={thumbUrl(comic.id, i)}
                  alt={`第 ${i + 1} 页缩略图`}
                  loading="lazy"
                  decoding="async"
                  draggable={false}
                />
                <span className="thumb-no">{i + 1}</span>
                {bookmarksEnabled && bookmarkSet.has(i) && <span className="thumb-bookmark" />}
              </button>
            )
          })}
        </div>
      </div>
    </div>
  )
}
