import { useEffect, useRef, type RefObject } from 'react'

/** 点击元素外部时触发（下拉菜单收起用） */
export function useClickOutside<T extends HTMLElement>(
  onOutside: () => void
): RefObject<T> {
  const ref = useRef<T>(null)
  useEffect(() => {
    const onDown = (e: MouseEvent): void => {
      if (ref.current && !ref.current.contains(e.target as Node)) onOutside()
    }
    document.addEventListener('mousedown', onDown)
    return () => document.removeEventListener('mousedown', onDown)
  }, [onOutside])
  return ref
}
