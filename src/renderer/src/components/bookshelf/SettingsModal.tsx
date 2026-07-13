import type { ReactNode } from 'react'
import type { CardSize, ReadingDirection, ReadingMode, ThemeMode, ZoomMode } from '@shared/types'
import Modal from '@/components/common/Modal'
import Segmented from '@/components/common/Segmented'
import { useSettings } from '@/store/settings'

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
    </Modal>
  )
}
