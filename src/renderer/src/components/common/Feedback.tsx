import type { ReactNode } from 'react'
import { useUi } from '@/store/ui'

export function Spinner({ size = 22 }: { size?: number }): ReactNode {
  return <span className="spinner" style={{ width: size, height: size }} aria-label="加载中" />
}

/** 全局轻提示 */
export function Toasts(): ReactNode {
  const toasts = useUi((s) => s.toasts)
  const dismiss = useUi((s) => s.dismiss)
  if (toasts.length === 0) return null
  return (
    <div className="toasts">
      {toasts.map((t) => (
        <div key={t.id} className={`toast toast-${t.kind}`} onClick={() => dismiss(t.id)}>
          {t.text}
        </div>
      ))}
    </div>
  )
}
