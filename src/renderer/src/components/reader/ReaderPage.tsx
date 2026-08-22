import { useCallback, type ReactNode } from 'react'
import type { ZoomMode } from '@shared/types'
import PageImage from '@/components/reader/PageImage'
import { useAutoCrop } from '@/hooks/useAutoCrop'
import { pageUrl } from '@/utils/comicUrl'

interface ReaderPageProps {
  comicId: string
  index: number
  fit: ZoomMode
  scale: number
  boxW: number
  boxH: number
  /** 自动裁掉扫描白边 */
  autoCrop: boolean
  eager?: boolean
  /** 图片加载后回报原始尺寸（跨页判定用） */
  onNatural?: (index: number, width: number, height: number) => void
  onSettled?: () => void
}

/**
 * 阅读器里的一页。
 * 单独成组件是因为自动裁边要用 hook，而一屏的页数（单页 / 双页 / 跨页）是变化的，
 * 不能在父组件里按数组循环调用 hook。
 */
export default function ReaderPage({
  comicId,
  index,
  fit,
  scale,
  boxW,
  boxH,
  autoCrop,
  eager,
  onNatural,
  onSettled
}: ReaderPageProps): ReactNode {
  const src = pageUrl(comicId, index)
  const crop = useAutoCrop(src, autoCrop)
  const handleNatural = useCallback(
    (w: number, h: number) => onNatural?.(index, w, h),
    [onNatural, index]
  )

  return (
    <PageImage
      src={src}
      alt={`第 ${index + 1} 页`}
      fit={fit}
      scale={scale}
      boxW={boxW}
      boxH={boxH}
      crop={crop}
      eager={eager}
      onNatural={handleNatural}
      onSettled={onSettled}
    />
  )
}
