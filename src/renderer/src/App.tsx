import { useEffect, useRef, useState, type ReactNode } from 'react'
import Bookshelf from '@/pages/Bookshelf'
import Reader from '@/pages/Reader'
import ErrorBoundary from '@/components/common/ErrorBoundary'
import { Spinner, Toasts } from '@/components/common/Feedback'
import { useLibrary } from '@/store/library'
import { useReader } from '@/store/reader'
import { applyTheme, useSettings } from '@/store/settings'
import { useUpdater } from '@/store/updater'

let bootStarted = false // StrictMode 下 effect 会执行两次，启动流程只跑一次

export default function App(): ReactNode {
  const readerActive = useReader((s) => s.active)
  const theme = useSettings((s) => s.settings.theme)
  const [ready, setReady] = useState(false)
  const readyRef = useRef(false)

  // 启动：加载设置和书架 → 按需自动打开上次阅读的漫画
  useEffect(() => {
    const offImport = window.api.onImportProgress((p) =>
      useLibrary.getState().setImportProgress(p)
    )
    const offUpdate = window.api.onUpdateEvent((e) => useUpdater.getState().handleEvent(e))
    if (!bootStarted) {
      bootStarted = true
      void (async () => {
        await useSettings.getState().load()
        applyTheme(useSettings.getState().settings.theme)
        await useLibrary.getState().load()
        const { settings } = useSettings.getState()
        if (settings.openLastOnStartup && settings.lastOpenedComicId) {
          const exists = useLibrary
            .getState()
            .comics.some((c) => c.id === settings.lastOpenedComicId)
          if (exists) void useReader.getState().open(settings.lastOpenedComicId)
        }
        readyRef.current = true
        setReady(true)
      })()
    } else if (readyRef.current) {
      setReady(true)
    }
    return () => {
      offImport()
      offUpdate()
    }
  }, [])

  // 主题变化实时生效；跟随系统时监听系统切换
  useEffect(() => {
    applyTheme(theme)
    if (theme !== 'system') return
    const mq = window.matchMedia('(prefers-color-scheme: dark)')
    const onChange = (): void => applyTheme('system')
    mq.addEventListener('change', onChange)
    return () => mq.removeEventListener('change', onChange)
  }, [theme])

  if (!ready) {
    return (
      <div className="boot">
        <Spinner size={26} />
      </div>
    )
  }

  return (
    <ErrorBoundary>
      <Bookshelf />
      {readerActive && <Reader />}
      <Toasts />
    </ErrorBoundary>
  )
}
