import {
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type CSSProperties,
  type ReactNode,
  type RefObject
} from 'react'
import { createPortal } from 'react-dom'

interface DropdownMenuProps {
  open: boolean
  /** 锚定元素（通常是触发按钮） */
  anchorRef: RefObject<HTMLElement | null>
  /** 右键菜单：以坐标为锚，优先于 anchorRef */
  point?: { x: number; y: number } | null
  align?: 'left' | 'right'
  onClose: () => void
  children: ReactNode
}

const EDGE_PX = 8
const GAP_PX = 6

/**
 * 通用下拉菜单：portal 到 body + fixed 定位。
 * 不受任何 overflow:hidden / 滚动容器裁剪，超出视口边缘自动收拢，
 * 底部放不下自动向上翻。外点/Esc/滚动/缩放窗口时关闭。
 */
export default function DropdownMenu({
  open,
  anchorRef,
  point,
  align = 'right',
  onClose,
  children
}: DropdownMenuProps): ReactNode {
  const menuRef = useRef<HTMLDivElement>(null)
  const [style, setStyle] = useState<CSSProperties>({ visibility: 'hidden' })

  // 打开后先渲染再测量真实尺寸，然后定位（同一帧内完成，无闪烁）
  useLayoutEffect(() => {
    if (!open) return
    const menu = menuRef.current
    if (!menu) return
    const rect = point
      ? { left: point.x, right: point.x, top: point.y, bottom: point.y }
      : anchorRef.current?.getBoundingClientRect()
    if (!rect) return
    const mw = menu.offsetWidth
    const mh = menu.offsetHeight
    let left = align === 'right' ? rect.right - mw : rect.left
    left = Math.min(Math.max(EDGE_PX, left), window.innerWidth - mw - EDGE_PX)
    let top = rect.bottom + GAP_PX
    if (top + mh > window.innerHeight - EDGE_PX) {
      top = Math.max(EDGE_PX, rect.top - mh - GAP_PX)
    }
    setStyle({ left, top, visibility: 'visible' })
  }, [open, point, align, anchorRef])

  useEffect(() => {
    if (!open) return
    const onDown = (e: MouseEvent): void => {
      const target = e.target as Node
      if (menuRef.current?.contains(target)) return
      if (anchorRef.current?.contains(target)) return
      onClose()
    }
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === 'Escape') {
        e.stopPropagation()
        onClose()
      }
    }
    const onScrollOrResize = (): void => onClose()
    document.addEventListener('mousedown', onDown)
    window.addEventListener('keydown', onKey, true)
    // capture 才能捕获内部滚动容器（书架列表）的滚动
    window.addEventListener('scroll', onScrollOrResize, true)
    window.addEventListener('resize', onScrollOrResize)
    return () => {
      document.removeEventListener('mousedown', onDown)
      window.removeEventListener('keydown', onKey, true)
      window.removeEventListener('scroll', onScrollOrResize, true)
      window.removeEventListener('resize', onScrollOrResize)
    }
  }, [open, onClose, anchorRef])

  if (!open) return null
  return createPortal(
    // portal 的合成事件仍会沿 React 树冒泡到卡片，必须拦下，否则点菜单项会顺带打开漫画
    <div
      ref={menuRef}
      className="dropdown-menu dropdown-portal"
      style={style}
      role="menu"
      onClick={(e) => e.stopPropagation()}
      onMouseDown={(e) => e.stopPropagation()}
      onContextMenu={(e) => {
        e.preventDefault()
        e.stopPropagation()
      }}
    >
      {children}
    </div>,
    document.body
  )
}
