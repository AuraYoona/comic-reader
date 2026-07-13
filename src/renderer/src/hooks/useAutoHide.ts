import { useCallback, useEffect, useRef, useState } from 'react'

/**
 * 阅读器工具栏自动隐藏。
 * - poke(): 鼠标活动时调用，显示并重新计时
 * - toggle(): 点击画面中央时切换
 * - pin(true): 鼠标悬停在工具栏上时暂停隐藏
 */
export function useAutoHide(delayMs: number): {
  visible: boolean
  poke: () => void
  toggle: () => void
  pin: (pinned: boolean) => void
} {
  const [visible, setVisible] = useState(true)
  const pinnedRef = useRef(false)
  const timerRef = useRef<number | null>(null)

  const clear = useCallback(() => {
    if (timerRef.current !== null) {
      window.clearTimeout(timerRef.current)
      timerRef.current = null
    }
  }, [])

  const arm = useCallback(() => {
    clear()
    timerRef.current = window.setTimeout(() => {
      if (!pinnedRef.current) setVisible(false)
    }, delayMs)
  }, [clear, delayMs])

  const poke = useCallback(() => {
    setVisible(true)
    arm()
  }, [arm])

  const toggle = useCallback(() => {
    setVisible((v) => {
      const nv = !v
      if (nv) arm()
      else clear()
      return nv
    })
  }, [arm, clear])

  const pin = useCallback(
    (pinned: boolean) => {
      pinnedRef.current = pinned
      if (pinned) {
        clear()
        setVisible(true)
      } else {
        arm()
      }
    },
    [arm, clear]
  )

  useEffect(() => {
    arm()
    return clear
  }, [arm, clear])

  return { visible, poke, toggle, pin }
}
