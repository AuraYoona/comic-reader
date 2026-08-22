import { useCallback, useEffect, useRef, useState, type CSSProperties, type RefObject } from 'react'

interface VirtualGridOptions {
  /** 条目总数 */
  count: number
  /** 单个卡片的最小宽度（决定列数） */
  minItemWidth: number
  /** 间距 */
  gap: number
  /** 封面（3:4）以下的信息区高度 */
  extraHeight: number
  /** 容器左右内边距（计算可用宽度用） */
  horizontalPadding?: number
  /** 上下各多渲染几行 */
  overscanRows?: number
}

export interface VirtualItem {
  index: number
  style: CSSProperties
}

interface VirtualGridResult {
  containerRef: RefObject<HTMLDivElement>
  onScroll: () => void
  /** 占位总高度（撑出滚动条） */
  totalHeight: number
  /** 当前需要渲染的条目及其绝对定位样式 */
  items: VirtualItem[]
  ready: boolean
}

/**
 * 书架虚拟滚动网格：固定 3:4 封面比例 + 固定信息区高度 → 行高可精确计算，
 * 只渲染可视行 ± overscan。上千本漫画时 DOM 始终只有几十个卡片。
 */
export function useVirtualGrid({
  count,
  minItemWidth,
  gap,
  extraHeight,
  horizontalPadding = 18,
  overscanRows = 2
}: VirtualGridOptions): VirtualGridResult {
  const containerRef = useRef<HTMLDivElement>(null)
  const rafRef = useRef(0)
  const [viewport, setViewport] = useState({ w: 0, h: 0 })
  const [scrollTop, setScrollTop] = useState(0)

  useEffect(() => {
    const el = containerRef.current
    if (!el) return
    const ro = new ResizeObserver(() => setViewport({ w: el.clientWidth, h: el.clientHeight }))
    ro.observe(el)
    setViewport({ w: el.clientWidth, h: el.clientHeight })
    return () => ro.disconnect()
  }, [])

  const onScroll = useCallback(() => {
    const el = containerRef.current
    if (!el) return
    cancelAnimationFrame(rafRef.current)
    rafRef.current = requestAnimationFrame(() => setScrollTop(el.scrollTop))
  }, [])

  useEffect(() => () => cancelAnimationFrame(rafRef.current), [])

  const width = Math.max(0, viewport.w - horizontalPadding * 2)
  const ready = width > 0

  const cols = Math.max(1, Math.floor((width + gap) / (minItemWidth + gap)))
  const itemW = cols > 0 ? (width - (cols - 1) * gap) / cols : minItemWidth
  const rowH = (itemW * 4) / 3 + extraHeight + gap
  const rows = Math.ceil(count / cols)
  const totalHeight = rows > 0 ? rows * rowH - gap : 0

  const items: VirtualItem[] = []
  if (ready && count > 0) {
    const startRow = Math.max(0, Math.floor(scrollTop / rowH) - overscanRows)
    const endRow = Math.min(rows, Math.ceil((scrollTop + viewport.h) / rowH) + overscanRows)
    const from = startRow * cols
    const to = Math.min(count, endRow * cols)
    for (let index = from; index < to; index++) {
      const row = Math.floor(index / cols)
      const col = index % cols
      items.push({
        index,
        style: {
          position: 'absolute',
          top: Math.round(row * rowH),
          left: Math.round(col * (itemW + gap)),
          width: Math.round(itemW)
        }
      })
    }
  }

  return { containerRef, onScroll, totalHeight, items, ready }
}
