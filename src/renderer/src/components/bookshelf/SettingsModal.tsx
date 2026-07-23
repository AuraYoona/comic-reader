import { useEffect, useState, type ReactNode } from 'react'
import type {
  CardSize,
  ExtensionId,
  ReadingDirection,
  ReadingMode,
  ThemeMode,
  ZoomMode
} from '@shared/types'
import Modal from '@/components/common/Modal'
import Segmented from '@/components/common/Segmented'
import { useSettings } from '@/store/settings'
import { useUpdater } from '@/store/updater'

/** 扩展功能注册表：新增扩展时在这里补一条开关文案即可 */
const EXTENSIONS: { id: ExtensionId; name: string; hint: string }[] = [
  {
    id: 'categories',
    name: '自定义分类',
    hint: '创建分类整理书架，入口在顶栏与卡片菜单；关闭不会删除数据'
  }
]

/** 「关于与更新」区块：当前版本、自动检查开关、检查/下载/安装的完整流程 */
function UpdateSection(): ReactNode {
  const settings = useSettings((s) => s.settings)
  const update = useSettings((s) => s.update)
  const updater = useUpdater()
  const [appVersion, setAppVersion] = useState('')

  useEffect(() => {
    void window.api.getAppVersion().then(setAppVersion)
  }, [])

  let action: ReactNode
  switch (updater.status) {
    case 'checking':
      action = (
        <button className="btn" disabled>
          检查中…
        </button>
      )
      break
    case 'available':
      action = (
        <button className="btn btn-primary" onClick={() => void updater.download()}>
          下载 v{updater.version}
        </button>
      )
      break
    case 'downloading':
      action = (
        <div className="update-progress" role="progressbar" aria-valuenow={updater.percent}>
          <div className="update-progress-bar" style={{ width: `${updater.percent}%` }} />
          <span>{Math.floor(updater.percent)}%</span>
        </div>
      )
      break
    case 'downloaded':
      action = (
        <button className="btn btn-primary" onClick={() => void updater.install()}>
          重启并安装 v{updater.version}
        </button>
      )
      break
    default:
      action = (
        <button className="btn" onClick={() => void updater.check(true)}>
          检查更新
        </button>
      )
  }

  return (
    <>
      <div className="settings-section">关于与更新</div>
      <div className="settings-row">
        <div className="settings-label">
          <span>启动时自动检查更新</span>
          <small>仅提示新版本，下载与安装始终由你确认</small>
        </div>
        <button
          className={settings.autoCheckUpdates ? 'switch on' : 'switch'}
          role="switch"
          aria-checked={settings.autoCheckUpdates}
          onClick={() => void update({ autoCheckUpdates: !settings.autoCheckUpdates })}
        >
          <span className="switch-knob" />
        </button>
      </div>
      <div className="settings-row">
        <div className="settings-label">
          <span>当前版本 {appVersion ? `v${appVersion}` : ''}</span>
          {updater.status === 'error' && <small className="update-error">{updater.error}</small>}
          {updater.status === 'downloaded' && <small>下载完成，也会在下次退出时自动安装</small>}
        </div>
        {action}
      </div>
    </>
  )
}

/** 全局设置弹窗，改动即时保存 */
export default function SettingsModal({ onClose }: { onClose: () => void }): ReactNode {
  const settings = useSettings((s) => s.settings)
  const update = useSettings((s) => s.update)

  return (
    <Modal title="设置" onClose={onClose}>
      <div className="settings-row">
        <div className="settings-label">
          <span>主题</span>
          <small>深色更适合长时间阅读</small>
        </div>
        <Segmented<ThemeMode>
          value={settings.theme}
          onChange={(v) => void update({ theme: v })}
          options={[
            { value: 'light', label: '浅色' },
            { value: 'dark', label: '深色' },
            { value: 'system', label: '跟随系统' }
          ]}
        />
      </div>

      <div className="settings-row">
        <div className="settings-label">
          <span>书架卡片大小</span>
        </div>
        <Segmented<CardSize>
          value={settings.cardSize}
          onChange={(v) => void update({ cardSize: v })}
          options={[
            { value: 'small', label: '小' },
            { value: 'medium', label: '中' },
            { value: 'large', label: '大' }
          ]}
        />
      </div>

      <div className="settings-row">
        <div className="settings-label">
          <span>阅读方向</span>
          <small>日漫通常为从右到左</small>
        </div>
        <Segmented<ReadingDirection>
          value={settings.readingDirection}
          onChange={(v) => void update({ readingDirection: v })}
          options={[
            { value: 'ltr', label: '从左到右' },
            { value: 'rtl', label: '从右到左' }
          ]}
        />
      </div>

      <div className="settings-row">
        <div className="settings-label">
          <span>默认阅读模式</span>
          <small>每本漫画的调整会单独记住</small>
        </div>
        <Segmented<ReadingMode>
          value={settings.defaultMode}
          onChange={(v) => void update({ defaultMode: v })}
          options={[
            { value: 'single', label: '单页' },
            { value: 'double', label: '双页' },
            { value: 'scroll', label: '连续滚动' }
          ]}
        />
      </div>

      <div className="settings-row">
        <div className="settings-label">
          <span>默认缩放模式</span>
        </div>
        <Segmented<ZoomMode>
          value={settings.defaultZoom}
          onChange={(v) => void update({ defaultZoom: v })}
          options={[
            { value: 'fitWidth', label: '适应宽度' },
            { value: 'fitHeight', label: '适应高度' },
            { value: 'original', label: '原始大小' }
          ]}
        />
      </div>

      <div className="settings-row">
        <div className="settings-label">
          <span>启动时打开上次阅读的漫画</span>
        </div>
        <button
          className={settings.openLastOnStartup ? 'switch on' : 'switch'}
          role="switch"
          aria-checked={settings.openLastOnStartup}
          onClick={() => void update({ openLastOnStartup: !settings.openLastOnStartup })}
        >
          <span className="switch-knob" />
        </button>
      </div>

      <div className="settings-section">扩展功能</div>
      {EXTENSIONS.map((ext) => (
        <div key={ext.id} className="settings-row">
          <div className="settings-label">
            <span>{ext.name}</span>
            <small>{ext.hint}</small>
          </div>
          <button
            className={settings.extensions[ext.id] ? 'switch on' : 'switch'}
            role="switch"
            aria-checked={settings.extensions[ext.id]}
            onClick={() =>
              void update({
                extensions: { ...settings.extensions, [ext.id]: !settings.extensions[ext.id] }
              })
            }
          >
            <span className="switch-knob" />
          </button>
        </div>
      ))}

      <UpdateSection />
    </Modal>
  )
}
