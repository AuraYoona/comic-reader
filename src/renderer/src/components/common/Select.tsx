import { useCallback, useEffect, useRef, useState, type KeyboardEvent, type ReactNode } from 'react'
import DropdownMenu from './DropdownMenu'
import { Icon } from './Icon'

export interface SelectOption<T extends string> {
  value: T
  label: string
  /** 选项前的色点（如分类颜色），形如 #rrggbb */
  dot?: string
}

interface SelectProps<T extends string> {
  value: T
  options: SelectOption<T>[]
  onChange: (v: T) => void
  /** 触发按钮无可视文字标签时提供给屏幕阅读器 */
  ariaLabel?: string
}

/**
 * 自定义下拉选择器：替代原生 <select>，与磨砂玻璃 UI 一致。
 * 菜单复用 DropdownMenu（portal + 自动翻转），支持方向键 / Home / End 导航，
 * Esc 或外点关闭后焦点交还触发按钮。
 */
export default function Select<T extends string>({
  value,
  options,
  onChange,
  ariaLabel
}: SelectProps<T>): ReactNode {
  const [open, setOpen] = useState(false)
  const btnRef = useRef<HTMLButtonElement>(null)
  const listRef = useRef<HTMLDivElement>(null)
  const wasOpen = useRef(false)
  const close = useCallback(() => setOpen(false), [])

  const selected = options.find((o) => o.value === value)
  // 任一选项带色点时，无色点选项也占位，保证文字左对齐
  const hasDots = options.some((o) => o.dot)

  // 打开后聚焦当前选中项；关闭时若焦点因菜单卸载而丢到 body，还给触发按钮。
  // DropdownMenu 首帧以 visibility:hidden 渲染测量，而 React 会在其定位提交前
  // 先冲刷本 effect，对不可见元素 focus() 是静默 no-op —— 推迟到微任务里
  // （此时定位已同步完成、菜单可见）再聚焦。
  useEffect(() => {
    if (open) {
      wasOpen.current = true
      queueMicrotask(() => {
        const list = listRef.current
        if (!list) return
        const target =
          list.querySelector<HTMLButtonElement>('[aria-selected="true"]') ??
          list.querySelector<HTMLButtonElement>('button')
        target?.focus()
      })
    } else if (wasOpen.current) {
      wasOpen.current = false
      if (document.activeElement === document.body) btnRef.current?.focus()
    }
  }, [open])

  const onTriggerKeyDown = (e: KeyboardEvent): void => {
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault()
      setOpen(true)
    }
  }

  const onListKeyDown = (e: KeyboardEvent): void => {
    // 原生 select 的行为：弹层打开时按 Tab 收起并把焦点留在触发按钮上
    if (e.key === 'Tab') {
      e.preventDefault()
      close()
      return
    }
    if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp' && e.key !== 'Home' && e.key !== 'End') return
    e.preventDefault()
    e.stopPropagation()
    const items = Array.from(listRef.current?.querySelectorAll<HTMLButtonElement>('button') ?? [])
    if (items.length === 0) return
    const i = items.indexOf(document.activeElement as HTMLButtonElement)
    const next =
      e.key === 'Home'
        ? items[0]
        : e.key === 'End'
          ? items[items.length - 1]
          : e.key === 'ArrowDown'
            ? items[Math.min(i + 1, items.length - 1)]
            : items[Math.max(i - 1, 0)]
    next.focus()
  }

  const pick = (v: T): void => {
    close()
    btnRef.current?.focus()
    if (v !== value) onChange(v)
  }

  return (
    <>
      <button
        ref={btnRef}
        type="button"
        className={open ? 'select-trigger open' : 'select-trigger'}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-label={ariaLabel}
        title={selected?.label}
        onClick={() => setOpen((v) => !v)}
        onKeyDown={onTriggerKeyDown}
      >
        {selected?.dot && <span className="cat-dot" style={{ background: selected.dot }} />}
        <span className="select-trigger-label">{selected?.label ?? ''}</span>
        <span className="select-caret">
          <Icon name="chevron-down" size={14} />
        </span>
      </button>
      <DropdownMenu
        open={open}
        anchorRef={btnRef}
        align="left"
        onClose={close}
        className="select-menu"
        role="listbox"
        matchAnchorWidth
      >
        <div ref={listRef} className="select-list" role="presentation" onKeyDown={onListKeyDown}>
          {options.map((o) => (
            <button
              key={o.value}
              type="button"
              role="option"
              aria-selected={o.value === value}
              title={o.label}
              className={o.value === value ? 'select-option selected' : 'select-option'}
              onClick={() => pick(o.value)}
              // 悬停即接管焦点：鼠标与键盘共用同一个"游标"高亮，不会出现两行同时高亮
              onMouseEnter={(e) => e.currentTarget.focus()}
            >
              {hasDots && (
                <span className="cat-dot" style={{ background: o.dot ?? 'transparent' }} />
              )}
              <span className="select-option-label">{o.label}</span>
              {o.value === value && (
                <span className="select-check">
                  <Icon name="check" size={14} />
                </span>
              )}
            </button>
          ))}
        </div>
      </DropdownMenu>
    </>
  )
}
