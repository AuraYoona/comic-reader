import { useEffect, useMemo, useState, type CSSProperties, type ReactNode } from 'react'
import type { ZoomMode } from '@shared/types'

interface PageImageProps {
  src: string
  alt: string
  fit: ZoomMode
  scale: number
  /** 可用区域（px），fitWidth/fitHeight 据此计算尺寸 */
  boxW: number
  boxH: number
  eager?: boolean
  onImageLoad?: (el: HTMLImageElement) => void
  /** 加载结束（无论成功失败）——翻页模式的慢加载指示用 */
  onSettled?: () => void
}

/**
 * 单张漫画页：按缩放模式计算尺寸，加载失败时显示占位并可重试。
 * 原始大小模式需要等图片加载拿到 naturalWidth 后才能应用倍率。
 */
export default function PageImage({
  src,
  alt,
  fit,
  scale,
  boxW,
  boxH,
  eager,
  onImageLoad,
  onSettled
}: PageImageProps): ReactNode {
  const [failed, setFailed] = useState(false)
  const [attempt, setAttempt] = useState(0)
  const [natural, setNatural] = useState<{ w: number; h: number } | null>(null)

  useEffect(() => {
    setFailed(false)
    setNatural(null)
    setAttempt(0)
  }, [src])

  const style = useMemo<CSSProperties>(() => {
    if (fit === 'fitWidth') return { width: Math.max(60, Math.round(boxW * scale)) }
    if (fit === 'fitHeight') return { height: Math.max(60, Math.round(boxH * scale)) }
    if (natural) return { width: Math.max(30, Math.round(natural.w * scale)) }
    return {}
  }, [fit, scale, boxW, boxH, natural])

  if (failed) {
    return (
      <div
        className="page-fallback"
        style={{ width: Math.max(240, Math.round(boxW * 0.7)), height: Math.round(boxH * 0.5) }}
      >
        <span>图片加载失败</span>
        <small>文件可能已损坏或被移动</small>
        <button
          className="btn btn-sm"
          onClick={(e) => {
            e.stopPropagation()
            setFailed(false)
            setAttempt((a) => a + 1)
          }}
        >
          重试
        </button>
      </div>
    )
  }

  return (
    <img
      className="page-img"
      style={style}
      src={attempt > 0 ? `${src}?retry=${attempt}` : src}
      alt={alt}
      draggable={false}
      decoding="async"
      loading={eager ? 'eager' : 'lazy'}
      onError={() => {
        setFailed(true)
        onSettled?.()
      }}
      onLoad={(e) => {
        const el = e.currentTarget
        setNatural({ w: el.naturalWidth, h: el.naturalHeight })
        onImageLoad?.(el)
        onSettled?.()
      }}
    />
  )
}
