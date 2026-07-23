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
  /** 追加到菜单容器上的类名（如 select-menu） */
  className?: string
  /** 语义角色：菜单或下拉选择列表 */
  role?: 'menu' | 'listbox'
  /** 菜单最小宽度与锚定元素对齐（下拉选择器用） */
  matchAnchorWidth?: boolean
  children: ReactNode
}

const EDGE_PX = 8
const GAP_PX = 6

/**
 * 吞掉紧随其后的一次 click（解散菜单的那次按下合成的）。
 * 原生 select 的系统弹层有同样行为；不吞的话这次点击会穿透到
 * 底下的卡片/按钮，误开漫画或误触开关。新手势或超时自动解除。
 */
function swallowNextClick(): void {
  const swallow = (e: MouseEvent): void => {
    e.preventDefault()
    e.stopPropagation()
    cleanup()
  }
  const cleanup = (): void => {
    window.removeEventListener('click', swallow, true)
    window.removeEventListener('mousedown', cleanup, true)
    window.clearTimeout(timer)
  }
  window.addEventListener('click', swallow, true)
  window.addEventListener('mousedown', cleanup, true)
  const timer = window.setTimeout(cleanup, 700)
}

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
  className,
  role = 'menu',
  matchAnchorWidth = false,
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
      ? { left: point.x, right: point.x, top: point.y, bottom: point.y, width: 0 }
      : anchorRef.current?.getBoundingClientRect()
    if (!rect) return
    // 先应用最小宽度再测量，否则翻转/收拢计算用的是未撑开的宽度
    const minWidth = matchAnchorWidth && rect.width > 0 ? rect.width : undefined
    if (minWidth) menu.style.minWidth = `${minWidth}px`
    const mw = menu.offsetWidth
    const mh = menu.offsetHeight
    let left = align === 'right' ? rect.right - mw : rect.left
    left = Math.min(Math.max(EDGE_PX, left), window.innerWidth - mw - EDGE_PX)
    let top = rect.bottom + GAP_PX
    if (top + mh > window.innerHeight - EDGE_PX) {
      top = Math.max(EDGE_PX, rect.top - mh - GAP_PX)
    }
    setStyle({ left, top, minWidth, visibility: 'visible' })
  }, [open, point, align, anchorRef, matchAnchorWidth])

  useEffect(() => {
    if (!open) return
    const onDown = (e: MouseEvent): void => {
      const target = e.target as Node
      if (menuRef.current?.contains(target)) return
      if (anchorRef.current?.contains(target)) return
      swallowNextClick()
      onClose()
    }
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === 'Escape') {
        e.stopPropagation()
        onClose()
      }
    }
    // 菜单自身可滚动（如下拉选择列表）：内部滚动不关闭，只有外部容器滚动才关
    const onScroll = (e: Event): void => {
      if (e.target instanceof Node && menuRef.current?.contains(e.target)) return
      onClose()
    }
    const onResize = (): void => onClose()
    document.addEventListener('mousedown', onDown)
    window.addEventListener('keydown', onKey, true)
    // capture 才能捕获内部滚动容器（书架列表）的滚动
    window.addEventListener('scroll', onScroll, true)
    window.addEventListener('resize', onResize)
    return () => {
      document.removeEventListener('mousedown', onDown)
      window.removeEventListener('keydown', onKey, true)
      window.removeEventListener('scroll', onScroll, true)
      window.removeEventListener('resize', onResize)
    }
  }, [open, onClose, anchorRef])

  if (!open) return null
  return createPortal(
    // portal 的合成事件仍会沿 React 树冒泡到卡片，必须拦下，否则点菜单项会顺带打开漫画
    <div
      ref={menuRef}
      className={className ? `dropdown-menu dropdown-portal ${className}` : 'dropdown-menu dropdown-portal'}
      style={style}
      role={role}
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
