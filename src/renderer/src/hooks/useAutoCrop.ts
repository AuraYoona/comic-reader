import { useEffect, useState } from 'react'
import type { CropInsets } from '@shared/crop'
import { getCachedCrop, measureCrop } from '@/lib/autoCrop'

/**
 * 算出某张图该裁掉的白边比例。
 * 命中缓存时同步返回，避免开着自动裁边翻页会闪一下未裁的原图。
 */
export function useAutoCrop(url: string, enabled: boolean): CropInsets | null {
  const [insets, setInsets] = useState<CropInsets | null>(() =>
    enabled ? (getCachedCrop(url) ?? null) : null
  )

  useEffect(() => {
    if (!enabled) {
      setInsets(null)
      return
    }
    const cached = getCachedCrop(url)
    if (cached !== undefined) {
      setInsets(cached)
      return
    }
    setInsets(null)
    let alive = true
    void measureCrop(url).then((value) => {
      if (alive) setInsets(value)
    })
    return () => {
      alive = false
    }
  }, [url, enabled])

  return insets
}
