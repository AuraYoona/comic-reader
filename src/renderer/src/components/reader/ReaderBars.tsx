import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react'
import type { ReadingDirection, ReadingMode, ZoomMode } from '@shared/types'
import DropdownMenu from '@/components/common/DropdownMenu'
import { Icon } from '@/components/common/Icon'
import Segmented from '@/components/common/Segmented'
import ThumbStrip from '@/components/reader/ThumbStrip'
import { useReader } from '@/store/reader'
import { useSettings } from '@/store/settings'

interface BarProps {
  visible: boolean
  pin: (pinned: boolean) => void
}

function pageLabel(page: number, pageCount: number, spread: number): string {
  if (pageCount === 0) return '- / -'
  if (spread > 1) return `${page + 1}-${page + spread} / ${pageCount}`
  return `${page + 1} / ${pageCount}`
}

/** 可输入的页码框：随外部翻页同步，回车跳转 */
function PageJump(): ReactNode {
  const page = useReader((s) => s.page)
  const pageCount = useReader((s) => s.pageCount)
  const mode = useReader((s) => s.mode)
  const setPage = useReader((s) => s.setPage)
  const [draft, setDraft] = useState(String(page + 1))
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => setDraft(String(page + 1)), [page])

  const commit = (): void => {
    const n = Number.parseInt(draft, 10)
    if (Number.isFinite(n)) setPage(n - 1)
    setDraft(String(useReader.getState().page + 1))
  }

  return (
    <span className="reader-pageinfo" title={pageLabel(page, pageCount, mode === 'double' ? 2 : 1)}>
      <input
        ref={inputRef}
        className="page-input"
        value={draft}
        inputMode="numeric"
        aria-label="跳转到指定页"
        onChange={(e) => setDraft(e.target.value.replace(/[^\d]/g, ''))}
        onFocus={(e) => e.currentTarget.select()}
        onBlur={commit}
        onKeyDown={(e) => {
          if (e.key === 'Enter') {
            e.preventDefault()
            commit()
            inputRef.current?.blur()
          } else if (e.key === 'Escape') {
            e.stopPropagation()
            setDraft(String(page + 1))
            inputRef.current?.blur()
          }
        }}
      />
      <span className="page-total">/ {pageCount}</span>
    </span>
  )
}

/** 书签：收藏当前页 + 跳到已收藏的页 */
function BookmarkControls(): ReactNode {
  const page = useReader((s) => s.page)
  const bookmarks = useReader((s) => s.bookmarks)
  const toggleBookmark = useReader((s) => s.toggleBookmark)
  const setPage = useReader((s) => s.setPage)
  const [open, setOpen] = useState(false)
  const listBtnRef = useRef<HTMLButtonElement>(null)
  const close = useCallback(() => setOpen(false), [])

  const marked = bookmarks.includes(page)

  return (
    <>
      <button
        className={marked ? 'icon-btn active' : 'icon-btn'}
        onClick={() => void toggleBookmark()}
        title={marked ? '取消本页书签 (B)' : '给本页加书签 (B)'}
      >
        <Icon name={marked ? 'bookmark-filled' : 'bookmark'} size={17} />
      </button>
      <button
        ref={listBtnRef}
        className="icon-btn"
        disabled={bookmarks.length === 0}
        onClick={() => setOpen((v) => !v)}
        title={bookmarks.length > 0 ? `书签（${bookmarks.length}）` : '还没有书签'}
      >
        <Icon name="chevron-down" size={14} />
      </button>
      <DropdownMenu open={open} anchorRef={listBtnRef} align="right" onClose={close}>
        {bookmarks.map((p) => (
          <button
            key={p}
            onClick={() => {
              close()
              setPage(p)
            }}
          >
            <Icon name={p === page ? 'bookmark-filled' : 'bookmark'} size={14} />第 {p + 1} 页
          </button>
        ))}
      </DropdownMenu>
    </>
  )
}

export function ReaderTopBar({
  visible,
  pin,
  isFullscreen,
  onToggleFullscreen
}: BarProps & { isFullscreen: boolean; onToggleFullscreen: () => void }): ReactNode {
  const comic = useReader((s) => s.comic)
  const close = useReader((s) => s.close)
  const bookmarksEnabled = useSettings((s) => s.settings.extensions.bookmarks)

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
      <PageJump />
      {bookmarksEnabled && <BookmarkControls />}
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
  const pageOffset = useReader((s) => s.pageOffset)
  const autoCrop = useReader((s) => s.autoCrop)
  const autoTurn = useReader((s) => s.autoTurn)
  const thumbStrip = useReader((s) => s.thumbStrip)
  const setPage = useReader((s) => s.setPage)
  const setMode = useReader((s) => s.setMode)
  const setZoom = useReader((s) => s.setZoom)
  const setScale = useReader((s) => s.setScale)
  const setDirection = useReader((s) => s.setDirection)
  const togglePageOffset = useReader((s) => s.togglePageOffset)
  const toggleAutoCrop = useReader((s) => s.toggleAutoCrop)
  const toggleAutoTurn = useReader((s) => s.toggleAutoTurn)
  const toggleThumbStrip = useReader((s) => s.toggleThumbStrip)
  const next = useReader((s) => s.next)
  const prev = useReader((s) => s.prev)
  const autoTurnSeconds = useSettings((s) => s.settings.autoTurnSeconds)

  const rtl = direction === 'rtl'

  return (
    <div
      className={visible ? 'reader-bar reader-bar-bottom' : 'reader-bar reader-bar-bottom hidden'}
      onMouseEnter={() => pin(true)}
      onMouseLeave={() => pin(false)}
    >
      {thumbStrip && <ThumbStrip />}

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
          <button
            className="icon-btn icon-btn-sm"
            onClick={() => setScale(scale - 0.1)}
            title="缩小 (-)"
          >
            −
          </button>
          <button className="zoom-value" onClick={() => setScale(1)} title="重置缩放 (0)">
            {Math.round(scale * 100)}%
          </button>
          <button
            className="icon-btn icon-btn-sm"
            onClick={() => setScale(scale + 0.1)}
            title="放大 (+)"
          >
            +
          </button>
        </div>

        {mode === 'double' && (
          <button
            className="btn btn-sm btn-ghost"
            onClick={togglePageOffset}
            title="双页配对偏移 (O)：封面单独占屏 / 从第一页起两两成对"
          >
            <Icon name="columns" size={14} />
            {pageOffset === 1 ? '封面单独' : '首页配对'}
          </button>
        )}

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

        <button
          className={autoCrop ? 'btn btn-sm btn-ghost active' : 'btn btn-sm btn-ghost'}
          onClick={toggleAutoCrop}
          title="自动裁掉扫描白边 (C)"
        >
          <Icon name="crop" size={14} />
          裁边
        </button>

        <button
          className={thumbStrip ? 'btn btn-sm btn-ghost active' : 'btn btn-sm btn-ghost'}
          onClick={toggleThumbStrip}
          title="缩略图跳页条 (T)"
        >
          <Icon name="film" size={14} />
          缩略图
        </button>

        <button
          className={autoTurn ? 'btn btn-sm btn-ghost active' : 'btn btn-sm btn-ghost'}
          onClick={toggleAutoTurn}
          title={`自动翻页 (A)：每 ${autoTurnSeconds} 秒一次`}
        >
          <Icon name={autoTurn ? 'pause' : 'clock'} size={14} />
          {autoTurn ? '停止' : '自动'}
        </button>
      </div>
    </div>
  )
}
