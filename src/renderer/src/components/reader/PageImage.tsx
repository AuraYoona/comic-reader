import { useEffect, useMemo, useState, type CSSProperties, type ReactNode } from 'react'
import type { CropInsets } from '@shared/crop'
import type { ZoomMode } from '@shared/types'

interface PageImageProps {
  src: string
  alt: string
  fit: ZoomMode
  scale: number
  /** 可用区域（px），fitWidth/fitHeight 据此计算尺寸 */
  boxW: number
  boxH: number
  /** 要裁掉的白边比例；裁掉的部分不占版面，缩放基准以裁后尺寸为准 */
  crop?: CropInsets | null
  eager?: boolean
  /** 图片加载后回报原始尺寸 */
  onNatural?: (width: number, height: number) => void
  /** 加载结束（无论成功失败）——翻页模式的慢加载指示用 */
  onSettled?: () => void
}

const pct = (v: number): string => `${(v * 100).toFixed(3)}%`

/**
 * 单张漫画页：按缩放模式计算尺寸，加载失败时显示占位并可重试。
 * 原始大小模式需要等图片加载拿到 naturalWidth 后才能应用倍率。
 *
 * 裁边用 clip-path 切掉留白，再用等量的负外边距把切掉的空间从版面里收回来，
 * 这样「适应宽度」量的就是裁后的内容宽度。
 */
export default function PageImage({
  src,
  alt,
  fit,
  scale,
  boxW,
  boxH,
  crop,
  eager,
  onNatural,
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
    const plain = (): CSSProperties => {
      if (fit === 'fitWidth') return { width: Math.max(60, Math.round(boxW * scale)) }
      if (fit === 'fitHeight') return { height: Math.max(60, Math.round(boxH * scale)) }
      if (natural) return { width: Math.max(30, Math.round(natural.w * scale)) }
      return {}
    }
    // 尺寸未知时无法把裁剪换算成像素，先按原样显示，加载完成后这里会重算
    if (!crop || !natural || natural.w <= 0 || natural.h <= 0) return plain()

    const keepW = 1 - crop.left - crop.right
    const keepH = 1 - crop.top - crop.bottom
    if (keepW <= 0 || keepH <= 0) return plain()
    const ratio = natural.h / natural.w

    let imgW: number
    let imgH: number
    if (fit === 'fitWidth') {
      imgW = Math.max(60, Math.round((boxW * scale) / keepW))
      imgH = Math.round(imgW * ratio)
    } else if (fit === 'fitHeight') {
      imgH = Math.max(60, Math.round((boxH * scale) / keepH))
      imgW = Math.round(imgH / ratio)
    } else {
      imgW = Math.max(30, Math.round(natural.w * scale))
      imgH = Math.round(imgW * ratio)
    }

    return {
      width: imgW,
      height: imgH,
      clipPath: `inset(${pct(crop.top)} ${pct(crop.right)} ${pct(crop.bottom)} ${pct(crop.left)})`,
      margin: [
        -Math.round(crop.top * imgH),
        -Math.round(crop.right * imgW),
        -Math.round(crop.bottom * imgH),
        -Math.round(crop.left * imgW)
      ]
        .map((v) => `${v}px`)
        .join(' '),
      // clip-path 会连投影一起切掉，裁边时干脆不要投影
      boxShadow: 'none'
    }
  }, [fit, scale, boxW, boxH, natural, crop])

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
        onNatural?.(el.naturalWidth, el.naturalHeight)
        onSettled?.()
      }}
    />
  )
}
