import { create } from 'zustand'

export type ToastKind = 'info' | 'success' | 'error'

export interface Toast {
  id: number
  kind: ToastKind
  text: string
}

interface UiState {
  toasts: Toast[]
  toast: (text: string, kind?: ToastKind) => void
  dismiss: (id: number) => void
}

let nextId = 1
const TOAST_MS = 4200
const MAX_TOASTS = 4

export const useUi = create<UiState>()((set) => ({
  toasts: [],

  toast: (text, kind = 'info') => {
    const id = nextId++
    // 超过上限丢最旧的，防止批量导入失败时刷屏
    set((s) => ({ toasts: [...s.toasts, { id, kind, text }].slice(-MAX_TOASTS) }))
    setTimeout(() => {
      set((s) => ({ toasts: s.toasts.filter((t) => t.id !== id) }))
    }, TOAST_MS)
  },

  dismiss: (id) => set((s) => ({ toasts: s.toasts.filter((t) => t.id !== id) }))
}))
