import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode
} from 'react'
import PageImage from '@/components/reader/PageImage'
import { prefetchImage } from '@/lib/pageCache'
import { useReader } from '@/store/reader'
import { pageUrl } from '@/utils/comicUrl'

const WHEEL_FLIP_COOLDOWN_MS = 170
const PAGE_GAP = 8
const SLOW_LOAD_HINT_MS = 200
const DRAG_THRESHOLD_PX = 5

/**
 * 单页 / 双页视图。
 * - 相邻页用 img.decode() 提前解码，翻页零白屏
 * - 缩放超出视口时可滚动 + 按住拖拽平移；滚轮在页面边缘才翻页
 * - 点击左/右 1/3 区域翻页（尊重阅读方向），中间切换工具栏
 * - 当前页 200ms 内没加载完显示轻量加载指示
 */
export default function PagedView({ onToggleBars }: { onToggleBars: () => void }): ReactNode {
  const comic = useReader((s) => s.comic)!
  const page = useReader((s) => s.page)
  const pageCount = useReader((s) => s.pageCount)
  const mode = useReader((s) => s.mode)
  const zoom = useReader((s) => s.zoom)
  const scale = useReader((s) => s.scale)
  const direction = useReader((s) => s.direction)

  const viewportRef = useRef<HTMLDivElement>(null)
  const [box, setBox] = useState({ w: 0, h: 0 })
  const [panning, setPanning] = useState(false)
  const [slowLoading, setSlowLoading] = useState(false)
  const lastPageRef = useRef(page)
  const wheelGateRef = useRef(0)
  const downPosRef = useRef<{ x: number; y: number } | null>(null)
  const settledRef = useRef(false)

  const double = mode === 'double'
  const indices = useMemo(() => {
    const list = double ? [page, page + 1] : [page]
    return list.filter((i) => i >= 0 && i < pageCount)
  }, [double, page, pageCount])

  // 视口尺寸（fitWidth/fitHeight 的基准）
  useEffect(() => {
    const el = viewportRef.current
    if (!el) return
    const ro = new ResizeObserver(() => setBox({ w: el.clientWidth, h: el.clientHeight }))
    ro.observe(el)
    setBox({ w: el.clientWidth, h: el.clientHeight })
    return () => ro.disconnect()
  }, [])

  // 翻页后回到页首（往回翻则到页尾，符合“继续往上看”的直觉）
  useEffect(() => {
    const el = viewportRef.current
    if (!el) return
    const goingBack = page < lastPageRef.current
    lastPageRef.current = page
    el.scrollTop = goingBack ? el.scrollHeight : 0
    el.scrollLeft = 0
  }, [page])

  // 慢加载指示：当前页 200ms 内没 settle 才显示，避免闪烁
  useEffect(() => {
    settledRef.current = false
    setSlowLoading(false)
    const t = window.setTimeout(() => {
      if (!settledRef.current) setSlowLoading(true)
    }, SLOW_LOAD_HINT_MS)
    return () => window.clearTimeout(t)
  }, [page, comic.id])
  const onFirstSettled = useCallback(() => {
    settledRef.current = true
    setSlowLoading(false)
  }, [])

  // 相邻页预取 + 预解码
  useEffect(() => {
    const around = double ? [2, 3, -2, -1, 4, 5] : [1, 2, -1, 3]
    for (const d of around) {
      const i = page + d
      if (i >= 0 && i < pageCount) prefetchImage(pageUrl(comic.id, i))
    }
  }, [page, double, pageCount, comic.id])

  // 滚轮：普通滚动优先，页面到边缘再翻页；Ctrl+滚轮缩放
  useEffect(() => {
    const el = viewportRef.current
    if (!el) return
    const onWheel = (e: WheelEvent): void => {
      const store = useReader.getState()
      if (e.ctrlKey) {
        e.preventDefault()
        store.setScale(store.scale + (e.deltaY < 0 ? 0.1 : -0.1))
        return
      }
      const flip = (forward: boolean): void => {
        const now = performance.now()
        if (now - wheelGateRef.current < WHEEL_FLIP_COOLDOWN_MS) return
        wheelGateRef.current = now
        forward ? store.next() : store.prev()
      }
      const canScroll = el.scrollHeight > el.clientHeight + 2
      if (!canScroll) {
        e.preventDefault()
        flip(e.deltaY > 0)
        return
      }
      const atBottom = el.scrollTop + el.clientHeight >= el.scrollHeight - 2
      const atTop = el.scrollTop <= 2
      if (e.deltaY > 0 && atBottom) {
        e.preventDefault()
        flip(true)
      } else if (e.deltaY < 0 && atTop) {
        e.preventDefault()
        flip(false)
      }
    }
    el.addEventListener('wheel', onWheel, { passive: false })
    return () => el.removeEventListener('wheel', onWheel)
  }, [])

  // 按住拖拽平移（放大后内容超出视口时）
  const onMouseDown = (e: React.MouseEvent): void => {
    if (e.button !== 0) return
    downPosRef.current = { x: e.clientX, y: e.clientY }
    const el = viewportRef.current
    if (!el) return
    const scrollable =
      el.scrollHeight > el.clientHeight + 2 || el.scrollWidth > el.clientWidth + 2
    if (!scrollable) return

    const start = { x: e.clientX, y: e.clientY, left: el.scrollLeft, top: el.scrollTop }
    let started = false
    const onMove = (ev: MouseEvent): void => {
      const dx = ev.clientX - start.x
      const dy = ev.clientY - start.y
      if (!started && Math.hypot(dx, dy) > DRAG_THRESHOLD_PX) {
        started = true
        setPanning(true)
      }
      if (started) {
        el.scrollLeft = start.left - dx
        el.scrollTop = start.top - dy
      }
    }
    const onUp = (): void => {
      window.removeEventListener('mousemove', onMove)
      window.removeEventListener('mouseup', onUp)
      setPanning(false)
    }
    window.addEventListener('mousemove', onMove)
    window.addEventListener('mouseup', onUp)
  }

  // 点击分区翻页（拖动/框选不算点击）
  const onClick = (e: React.MouseEvent): void => {
    const down = downPosRef.current
    if (down && Math.hypot(e.clientX - down.x, e.clientY - down.y) > DRAG_THRESHOLD_PX) return
    const width = viewportRef.current?.clientWidth ?? 0
    if (width === 0) return
    const store = useReader.getState()
    const ratio = e.clientX / width
    if (ratio < 0.32) {
      store.direction === 'ltr' ? store.prev() : store.next()
    } else if (ratio > 0.68) {
      store.direction === 'ltr' ? store.next() : store.prev()
    } else {
      onToggleBars()
    }
  }

  const perPageW = double ? Math.floor((box.w - PAGE_GAP) / 2) : box.w

  return (
    <div
      ref={viewportRef}
      className={panning ? 'paged-viewport panning' : 'paged-viewport'}
      onMouseDown={onMouseDown}
      onClick={onClick}
    >
      <div
        className="paged-canvas"
        style={{
          flexDirection: double && direction === 'rtl' ? 'row-reverse' : 'row',
          gap: PAGE_GAP
        }}
      >
        {indices.map((i, order) => (
          <PageImage
            key={`${comic.id}-${i}`}
            src={pageUrl(comic.id, i)}
            alt={`第 ${i + 1} 页`}
            fit={zoom}
            scale={scale}
            boxW={perPageW}
            boxH={box.h}
            eager
            onSettled={order === 0 ? onFirstSettled : undefined}
          />
        ))}
      </div>
      {slowLoading && (
        <div className="page-loading">
          <span className="spinner" style={{ width: 26, height: 26 }} />
        </div>
      )}
    </div>
  )
}
