import type { ReactNode } from 'react'
import type { ReadingDirection, ReadingMode, ZoomMode } from '@shared/types'
import { Icon } from '@/components/common/Icon'
import Segmented from '@/components/common/Segmented'
import { useReader } from '@/store/reader'

interface BarProps {
  visible: boolean
  pin: (pinned: boolean) => void
}

function pageLabel(page: number, pageCount: number, double: boolean): string {
  if (pageCount === 0) return '- / -'
  if (double && page + 1 < pageCount) return `${page + 1}-${page + 2} / ${pageCount}`
  return `${page + 1} / ${pageCount}`
}

export function ReaderTopBar({
  visible,
  pin,
  isFullscreen,
  onToggleFullscreen
}: BarProps & { isFullscreen: boolean; onToggleFullscreen: () => void }): ReactNode {
  const comic = useReader((s) => s.comic)
  const page = useReader((s) => s.page)
  const pageCount = useReader((s) => s.pageCount)
  const mode = useReader((s) => s.mode)
  const close = useReader((s) => s.close)

  return (
    <div
      className={visible ? 'reader-bar reader-bar-top' : 'reader-bar reader-bar-top hidden'}
      onMouseEnter={() => pin(true)}
      onMouseLeave={() => pin(false)}
    >
      <button className="icon-btn" onClick={close} title="返回书架 (Esc)">
        <Icon name="arrow-left" size={18} />
      </button>
      <div className="reader-title" title={comic?.sourcePath}>
        {comic?.title ?? ''}
      </div>
      <span className="reader-pageinfo">{pageLabel(page, pageCount, mode === 'double')}</span>
      <button
        className="icon-btn"
        onClick={onToggleFullscreen}
        title={isFullscreen ? '退出全屏 (F)' : '全屏 (F)'}
      >
        <Icon name={isFullscreen ? 'minimize' : 'maximize'} size={16} />
      </button>
    </div>
  )
}

export function ReaderBottomBar({ visible, pin }: BarProps): ReactNode {
  const page = useReader((s) => s.page)
  const pageCount = useReader((s) => s.pageCount)
  const mode = useReader((s) => s.mode)
  const zoom = useReader((s) => s.zoom)
  const scale = useReader((s) => s.scale)
  const direction = useReader((s) => s.direction)
  const setPage = useReader((s) => s.setPage)
  const setMode = useReader((s) => s.setMode)
  const setZoom = useReader((s) => s.setZoom)
  const setScale = useReader((s) => s.setScale)
  const setDirection = useReader((s) => s.setDirection)
  const next = useReader((s) => s.next)
  const prev = useReader((s) => s.prev)

  const rtl = direction === 'rtl'

  return (
    <div
      className={visible ? 'reader-bar reader-bar-bottom' : 'reader-bar reader-bar-bottom hidden'}
      onMouseEnter={() => pin(true)}
      onMouseLeave={() => pin(false)}
    >
      <div className="reader-slider-row">
        <button className="icon-btn" onClick={rtl ? next : prev} title={rtl ? '下一页' : '上一页'}>
          <Icon name="chevron-left" size={18} />
        </button>
        <input
          className="reader-slider"
          type="range"
          min={0}
          max={Math.max(0, pageCount - 1)}
          value={page}
          style={{ direction: rtl ? 'rtl' : 'ltr' }}
          onChange={(e) => setPage(Number(e.target.value))}
          title={`第 ${page + 1} 页`}
        />
        <button className="icon-btn" onClick={rtl ? prev : next} title={rtl ? '上一页' : '下一页'}>
          <Icon name="chevron-right" size={18} />
        </button>
      </div>

      <div className="reader-controls-row">
        <Segmented<ReadingMode>
          small
          value={mode}
          onChange={setMode}
          options={[
            { value: 'single', label: '单页', title: '单页 (1)' },
            { value: 'double', label: '双页', title: '双页 (2)' },
            { value: 'scroll', label: '滚动', title: '连续滚动 (3)' }
          ]}
        />

        <Segmented<ZoomMode>
          small
          value={zoom}
          onChange={setZoom}
          options={[
            { value: 'fitWidth', label: '适宽' },
            { value: 'fitHeight', label: '适高' },
            { value: 'original', label: '原始' }
          ]}
        />

        <div className="zoom-group">
          <button className="icon-btn icon-btn-sm" onClick={() => setScale(scale - 0.1)} title="缩小 (-)">
            −
          </button>
          <button className="zoom-value" onClick={() => setScale(1)} title="重置缩放 (0)">
            {Math.round(scale * 100)}%
          </button>
          <button className="icon-btn icon-btn-sm" onClick={() => setScale(scale + 0.1)} title="放大 (+)">
            +
          </button>
        </div>

        {mode !== 'scroll' && (
          <button
            className="btn btn-sm btn-ghost"
            onClick={() => setDirection((rtl ? 'ltr' : 'rtl') as ReadingDirection)}
            title="切换阅读方向"
          >
            <Icon name="swap" size={14} />
            {rtl ? '右→左' : '左→右'}
          </button>
        )}
      </div>
    </div>
  )
}
