import type { ReactNode } from 'react'

interface Option<T extends string> {
  value: T
  label: string
  title?: string
}

interface SegmentedProps<T extends string> {
  value: T
  options: Option<T>[]
  onChange: (v: T) => void
  small?: boolean
}

/** 分段单选控件（设置项、阅读器模式切换共用） */
export default function Segmented<T extends string>({
  value,
  options,
  onChange,
  small
}: SegmentedProps<T>): ReactNode {
  return (
    <div className={small ? 'seg seg-sm' : 'seg'} role="radiogroup">
      {options.map((o) => (
        <button
          key={o.value}
          role="radio"
          aria-checked={o.value === value}
          title={o.title}
          className={o.value === value ? 'seg-item active' : 'seg-item'}
          onClick={() => onChange(o.value)}
        >
          {o.label}
        </button>
      ))}
    </div>
  )
}
