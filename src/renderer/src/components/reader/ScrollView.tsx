import { useEffect, useRef, useState, type ReactNode } from 'react'
import PageImage from '@/components/reader/PageImage'
import { useReader } from '@/store/reader'
import { pageUrl } from '@/utils/comicUrl'

/** ScrollView 挂载时把滚动方法注册到这里，键盘（空格/方向键）滚动用 */
export const scrollBus: { scrollByViewport: ((fraction: number) => void) | null } = {
  scrollByViewport: null
}

const LOAD_MARGIN = '1800px 0px' // 视口上下各预载约 2 屏
const CURRENT_BAND = '-45% 0px -54.9% 0px' // 穿过屏幕中线的页算作当前页

/**
 * 长条连续滚动视图。
 * - 只挂载视口附近的图片，远处替换为等高占位，长篇不爆内存
 * - IntersectionObserver 侦测当前页并回写进度
 * - 外部跳页（进度条/键盘）时滚动到对应页
 */
export default function ScrollView({ onToggleBars }: { onToggleBars: () => void }): ReactNode {
  const comic = useReader((s) => s.comic)!
  const page = useReader((s) => s.page)
  const pageCount = useReader((s) => s.pageCount)
  const zoom = useReader((s) => s.zoom)
  const scale = useReader((s) => s.scale)

  const containerRef = useRef<HTMLDivElement>(null)
  const slotEls = useRef(new Map<number, HTMLDivElement>())
  const heights = useRef(new Map<number, number>())
  const lastReported = useRef(-1)
  const downPosRef = useRef<{ x: number; y: number } | null>(null)
  const [box, setBox] = useState({ w: 0, h: 0 })
  const [loaded, setLoaded] = useState<Set<number>>(() => new Set())

  useEffect(() => {
    const el = containerRef.current
    if (!el) return
    const ro = new ResizeObserver(() => setBox({ w: el.clientWidth, h: el.clientHeight }))
    ro.observe(el)
    setBox({ w: el.clientWidth, h: el.clientHeight })
    return () => ro.disconnect()
  }, [])

  // 观察所有页槽：进入预载范围就挂载图片，离开就卸载（记住高度防跳动）
  useEffect(() => {
    const root = containerRef.current
    if (!root) return

    const loadObs = new IntersectionObserver(
      (entries) => {
        setLoaded((prev) => {
          let next: Set<number> | null = null
          for (const en of entries) {
            const idx = Number((en.target as HTMLElement).dataset.index)
            if (Number.isNaN(idx)) continue
            if (en.isIntersecting && !prev.has(idx)) {
              next ??= new Set(prev)
              next.add(idx)
            } else if (!en.isIntersecting && prev.has(idx)) {
              const h = Math.round(en.boundingClientRect.height)
              if (h > 50) heights.current.set(idx, h)
              next ??= new Set(prev)
              next.delete(idx)
            }
          }
          return next ?? prev
        })
      },
      { root, rootMargin: LOAD_MARGIN }
    )

    const currentObs = new IntersectionObserver(
      (entries) => {
        for (const en of entries) {
          if (!en.isIntersecting) continue
          const idx = Number((en.target as HTMLElement).dataset.index)
          if (Number.isNaN(idx)) continue
          const store = useReader.getState()
          if (idx !== store.page) {
            lastReported.current = idx
            store.setPage(idx)
          } else {
            lastReported.current = idx
          }
        }
      },
      { root, rootMargin: CURRENT_BAND }
    )

    for (const el of slotEls.current.values()) {
      loadObs.observe(el)
      currentObs.observe(el)
    }
    return () => {
      loadObs.disconnect()
      currentObs.disconnect()
    }
  }, [pageCount, comic.id])

  // 外部改页（进度条 / 键盘 Home、End）→ 滚到对应页
  useEffect(() => {
    if (page === lastReported.current) return
    lastReported.current = page
    slotEls.current.get(page)?.scrollIntoView({ block: 'start' })
  }, [page])

  // 初始定位到上次阅读页；图片加载导致高度变化后再校正一次
  useEffect(() => {
    const target = useReader.getState().page
    lastReported.current = target
    slotEls.current.get(target)?.scrollIntoView({ block: 'start' })
    const timer = window.setTimeout(() => {
      slotEls.current.get(target)?.scrollIntoView({ block: 'start' })
    }, 350)
    return () => window.clearTimeout(timer)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [comic.id])

  // 注册键盘滚动 + Ctrl+滚轮缩放
  useEffect(() => {
    const el = containerRef.current
    if (!el) return
    scrollBus.scrollByViewport = (fraction) => {
      el.scrollBy({ top: el.clientHeight * fraction, behavior: 'auto' })
    }
    const onWheel = (e: WheelEvent): void => {
      if (!e.ctrlKey) return
      e.preventDefault()
      const store = useReader.getState()
      store.setScale(store.scale + (e.deltaY < 0 ? 0.1 : -0.1))
    }
    el.addEventListener('wheel', onWheel, { passive: false })
    return () => {
      el.removeEventListener('wheel', onWheel)
      scrollBus.scrollByViewport = null
    }
  }, [])

  const onMouseDown = (e: React.MouseEvent): void => {
    downPosRef.current = { x: e.clientX, y: e.clientY }
  }
  const onClick = (e: React.MouseEvent): void => {
    const down = downPosRef.current
    if (down && Math.hypot(e.clientX - down.x, e.clientY - down.y) > 6) return
    onToggleBars()
  }

  const placeholderW =
    zoom === 'fitWidth' ? Math.round(box.w * Math.min(scale, 1)) : Math.round(box.w * 0.7)

  return (
    <div ref={containerRef} className="scroll-view" onMouseDown={onMouseDown} onClick={onClick}>
      {Array.from({ length: pageCount }, (_, i) => (
        <div
          key={i}
          data-index={i}
          className="scroll-slot"
          ref={(el) => {
            if (el) slotEls.current.set(i, el)
            else slotEls.current.delete(i)
          }}
        >
          {loaded.has(i) ? (
            <PageImage
              src={pageUrl(comic.id, i)}
              alt={`第 ${i + 1} 页`}
              fit={zoom}
              scale={scale}
              boxW={box.w}
              boxH={box.h}
              eager
            />
          ) : (
            <div
              className="scroll-placeholder"
              style={{
                height: heights.current.get(i) ?? Math.max(420, Math.round(box.w * 1.2)),
                width: Math.max(200, placeholderW)
              }}
            >
              <span>{i + 1}</span>
            </div>
          )}
        </div>
      ))}
    </div>
  )
}
