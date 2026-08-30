import { useEffect, useState, type CSSProperties, type ReactNode } from 'react'
import { Icon } from '@/components/common/Icon'
import { Spinner } from '@/components/common/Feedback'
import PagedView from '@/components/reader/PagedView'
import ScrollView from '@/components/reader/ScrollView'
import { ReaderBottomBar, ReaderTopBar } from '@/components/reader/ReaderBars'
import { useAutoHide } from '@/hooks/useAutoHide'
import { scrollBus } from '@/lib/scrollBus'
import { useReader } from '@/store/reader'
import { setAutoTurnSeconds, useSettings } from '@/store/settings'

const BARS_HIDE_DELAY_MS = 2600

/**
 * 阅读器全屏覆盖层。
 * 键盘：← → 翻页（尊重阅读方向）、空格下一页、Esc 退出、F 全屏、
 *      PgUp/PgDn/Home/End、+/-/0 缩放、1/2/3 切换模式、
 *      B 书签、T 缩略图条、A 自动翻页、[ / ] 自动翻页间隔、O 双页偏移、C 自动裁边。
 */
export default function Reader(): ReactNode {
  const opening = useReader((s) => s.opening)
  const error = useReader((s) => s.error)
  const comic = useReader((s) => s.comic)
  const mode = useReader((s) => s.mode)
  const autoTurn = useReader((s) => s.autoTurn)
  const endHint = useReader((s) => s.endHint)
  const close = useReader((s) => s.close)
  const brightness = useSettings((s) => s.settings.brightness)
  const autoTurnSeconds = useSettings((s) => s.settings.autoTurnSeconds)

  const { visible, poke, toggle, pin } = useAutoHide(BARS_HIDE_DELAY_MS)
  const [isFullscreen, setIsFullscreen] = useState(false)

  // 窗口标题跟随当前漫画
  useEffect(() => {
    if (comic) document.title = `${comic.title} - 漫画阅读器`
    return () => {
      document.title = '漫画阅读器'
    }
  }, [comic])

  // 全屏状态同步
  useEffect(() => {
    void window.api.isFullscreen().then(setIsFullscreen)
    const off = window.api.onFullscreenChange(setIsFullscreen)
    return () => {
      off()
      void window.api.setFullscreen(false) // 关闭阅读器时确保退出全屏
    }
  }, [])

  const toggleFullscreen = (): void => {
    void window.api.isFullscreen().then((fs) => window.api.setFullscreen(!fs))
  }

  // 自动翻页：滚动模式按屏滚动，其余按屏翻页；翻到尽头时 next() 会自行停下
  useEffect(() => {
    if (!autoTurn) return
    const id = window.setInterval(() => {
      const store = useReader.getState()
      if (store.mode === 'scroll') scrollBus.scrollByViewport?.(0.85)
      else store.next()
    }, autoTurnSeconds * 1000)
    return () => window.clearInterval(id)
  }, [autoTurn, autoTurnSeconds])

  // 键盘快捷键（读 getState 避免闭包过期）
  useEffect(() => {
    const onKey = (e: KeyboardEvent): void => {
      const target = e.target as HTMLElement | null
      if (target && ['INPUT', 'SELECT', 'TEXTAREA'].includes(target.tagName)) return
      const store = useReader.getState()
      const inScroll = store.mode === 'scroll'
      // 字母快捷键不抢组合键
      const plain = !e.ctrlKey && !e.metaKey && !e.altKey

      switch (e.key) {
        case 'ArrowRight':
          e.preventDefault()
          store.direction === 'ltr' ? store.next() : store.prev()
          break
        case 'ArrowLeft':
          e.preventDefault()
          store.direction === 'ltr' ? store.prev() : store.next()
          break
        case 'ArrowDown':
          if (inScroll) {
            e.preventDefault()
            scrollBus.scrollByViewport?.(0.18)
          } else {
            e.preventDefault()
            store.next()
          }
          break
        case 'ArrowUp':
          if (inScroll) {
            e.preventDefault()
            scrollBus.scrollByViewport?.(-0.18)
          } else {
            e.preventDefault()
            store.prev()
          }
          break
        case ' ':
          e.preventDefault()
          if (inScroll) scrollBus.scrollByViewport?.(e.shiftKey ? -0.85 : 0.85)
          else if (e.shiftKey) store.prev()
          else store.next()
          break
        case 'PageDown':
          e.preventDefault()
          if (inScroll) scrollBus.scrollByViewport?.(0.9)
          else store.next()
          break
        case 'PageUp':
          e.preventDefault()
          if (inScroll) scrollBus.scrollByViewport?.(-0.9)
          else store.prev()
          break
        case 'Home':
          e.preventDefault()
          store.setPage(0)
          break
        case 'End':
          e.preventDefault()
          store.setPage(store.pageCount - 1)
          break
        case 'Escape':
          e.preventDefault()
          void window.api.isFullscreen().then((fs) => {
            if (fs) void window.api.setFullscreen(false)
            else store.close()
          })
          break
        case 'f':
        case 'F':
        case 'F11':
          e.preventDefault()
          void window.api.isFullscreen().then((fs) => window.api.setFullscreen(!fs))
          break
        case '+':
        case '=':
          store.setScale(store.scale + 0.1)
          break
        case '-':
          store.setScale(store.scale - 0.1)
          break
        case '0':
          store.setScale(1)
          break
        case '1':
          store.setMode('single')
          break
        case '2':
          store.setMode('double')
          break
        case '3':
          store.setMode('scroll')
          break
        case 'b':
        case 'B':
          if (plain && useSettings.getState().settings.extensions.bookmarks) {
            e.preventDefault()
            void store.toggleBookmark()
          }
          break
        case 't':
        case 'T':
          if (plain) {
            e.preventDefault()
            store.toggleThumbStrip()
          }
          break
        case 'a':
        case 'A':
          if (plain) {
            e.preventDefault()
            store.toggleAutoTurn()
          }
          break
        case '[':
          e.preventDefault()
          setAutoTurnSeconds(useSettings.getState().settings.autoTurnSeconds - 1)
          break
        case ']':
          e.preventDefault()
          setAutoTurnSeconds(useSettings.getState().settings.autoTurnSeconds + 1)
          break
        case 'o':
        case 'O':
          if (plain && store.mode === 'double') {
            e.preventDefault()
            store.togglePageOffset()
          }
          break
        case 'c':
        case 'C':
          if (plain) {
            e.preventDefault()
            store.toggleAutoCrop()
          }
          break
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  // 亮度滤镜只作用在漫画页上，工具栏保持原色
  const style = { '--reader-brightness': brightness } as CSSProperties

  return (
    <div className={visible ? 'reader' : 'reader cursor-idle'} style={style} onMouseMove={poke}>
      {opening && (
        <div className="reader-center">
          <Spinner size={28} />
          <p>正在打开…</p>
        </div>
      )}

      {!opening && error && (
        <div className="reader-center">
          <div className="state-icon">
            <Icon name="image" size={40} />
          </div>
          <p className="reader-error-text">{error}</p>
          <button className="btn btn-primary" onClick={close}>
            返回书架
          </button>
        </div>
      )}

      {!opening && !error && comic && (
        <>
          {mode === 'scroll' ? (
            <ScrollView onToggleBars={toggle} />
          ) : (
            <PagedView onToggleBars={toggle} />
          )}
          {endHint && (
            <div className="reader-end-hint">
              <strong>已是最后一页</strong>
              <span>再翻一次返回书架</span>
            </div>
          )}
          <ReaderTopBar
            visible={visible}
            pin={pin}
            isFullscreen={isFullscreen}
            onToggleFullscreen={toggleFullscreen}
          />
          <ReaderBottomBar visible={visible} pin={pin} />
        </>
      )}
    </div>
  )
}
