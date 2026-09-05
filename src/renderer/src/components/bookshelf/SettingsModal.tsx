import { useEffect, useState, type ReactNode } from 'react'
import {
  AUTO_TURN_MAX,
  AUTO_TURN_MIN,
  BRIGHTNESS_MAX,
  BRIGHTNESS_MIN,
  type CardSize,
  type ExtensionId,
  type ReadingDirection,
  type ReadingMode,
  type ThemeMode,
  type ZoomMode
} from '@shared/types'
import Modal from '@/components/common/Modal'
import Segmented from '@/components/common/Segmented'
import { Icon } from '@/components/common/Icon'
import { useLibrary } from '@/store/library'
import { useSettings } from '@/store/settings'
import { useUpdater } from '@/store/updater'

/** 扩展功能注册表：新增扩展时在这里补一条开关文案即可 */
const EXTENSIONS: { id: ExtensionId; name: string; hint: string }[] = [
  {
    id: 'categories',
    name: '自定义分类',
    hint: '创建分类整理书架，入口在顶栏与卡片菜单；关闭不会删除数据'
  },
  {
    id: 'bookmarks',
    name: '书签',
    hint: '阅读时按 B 收藏当前页，入口在阅读器顶栏；关闭不会删除已存的书签'
  }
]

/** 设置项通用行 */
function Row({
  label,
  hint,
  children
}: {
  label: string
  hint?: string
  children: ReactNode
}): ReactNode {
  return (
    <div className="settings-row">
      <div className="settings-label">
        <span>{label}</span>
        {hint && <small>{hint}</small>}
      </div>
      {children}
    </div>
  )
}

function Toggle({ on, onChange }: { on: boolean; onChange: (v: boolean) => void }): ReactNode {
  return (
    <button
      className={on ? 'switch on' : 'switch'}
      role="switch"
      aria-checked={on}
      onClick={() => onChange(!on)}
    >
      <span className="switch-knob" />
    </button>
  )
}

/** 漫画库根目录：记住之后可以增量扫描出新加进来的漫画 */
function LibraryRootsSection(): ReactNode {
  const settings = useSettings((s) => s.settings)
  const update = useSettings((s) => s.update)
  const replace = useSettings((s) => s.replace)
  const scanRoots = useLibrary((s) => s.scanRoots)
  const busy = useLibrary((s) => s.importing.active)

  const addRoot = async (): Promise<void> => {
    const next = await window.api.addLibraryRoot()
    replace(next)
  }

  const removeRoot = (root: string): void => {
    void update({ libraryRoots: settings.libraryRoots.filter((r) => r !== root) })
  }

  return (
    <>
      <div className="settings-section">漫画库目录</div>
      <Row label="启动时扫描库目录" hint="把根目录下新增的子文件夹 / 压缩包 / PDF 自动上架">
        <Toggle on={settings.autoScanRoots} onChange={(v) => void update({ autoScanRoots: v })} />
      </Row>

      {settings.libraryRoots.length > 0 && (
        <div className="root-list">
          {settings.libraryRoots.map((root) => (
            <div key={root} className="root-row">
              <Icon name="folder" size={14} />
              <span className="root-path" title={root}>
                {root}
              </span>
              <button
                className="icon-btn icon-btn-sm"
                title="不再扫描这个目录"
                onClick={() => removeRoot(root)}
              >
                <Icon name="close" size={13} />
              </button>
            </div>
          ))}
        </div>
      )}

      <div className="settings-row">
        <div className="settings-label">
          <span>
            {settings.libraryRoots.length > 0
              ? `已记录 ${settings.libraryRoots.length} 个根目录`
              : '还没有记录根目录'}
          </span>
          <small>「批量导入子文件夹」用过的目录会自动记进来</small>
        </div>
        <div className="settings-actions">
          <button className="btn btn-sm" onClick={() => void addRoot()}>
            <Icon name="plus" size={13} />
            添加目录…
          </button>
          <button
            className="btn btn-sm"
            disabled={busy || settings.libraryRoots.length === 0}
            onClick={() => void scanRoots()}
          >
            <Icon name="refresh" size={13} />
            立即扫描
          </button>
        </div>
      </div>
    </>
  )
}

/** 数据备份与恢复 */
function DataSection(): ReactNode {
  const backup = useLibrary((s) => s.backup)
  const restore = useLibrary((s) => s.restore)
  const [confirmReplace, setConfirmReplace] = useState(false)

  return (
    <>
      <div className="settings-section">数据备份</div>
      <Row label="导出" hint="把书架、分类、进度、书签与封面导出到一个文件夹">
        <button className="btn btn-sm" onClick={() => void backup()}>
          <Icon name="download" size={13} />
          导出备份…
        </button>
      </Row>
      <Row label="合并导入" hint="只补充书架里没有的漫画，已有的原样保留">
        <button className="btn btn-sm" onClick={() => void restore('merge')}>
          <Icon name="upload" size={13} />
          从备份合并…
        </button>
      </Row>
      <Row label="覆盖恢复" hint="用备份整体替换当前书架，恢复前会自动备份现有数据">
        {confirmReplace ? (
          <div className="settings-actions">
            <button className="btn btn-sm" onClick={() => setConfirmReplace(false)}>
              取消
            </button>
            <button
              className="btn btn-sm btn-danger"
              onClick={() => {
                setConfirmReplace(false)
                void restore('replace')
              }}
            >
              确定覆盖
            </button>
          </div>
        ) : (
          <button className="btn btn-sm" onClick={() => setConfirmReplace(true)}>
            <Icon name="upload" size={13} />
            覆盖恢复…
          </button>
        )}
      </Row>
    </>
  )
}

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
      <Row label="启动时自动检查更新" hint="仅提示新版本，下载与安装始终由你确认">
        <Toggle
          on={settings.autoCheckUpdates}
          onChange={(v) => void update({ autoCheckUpdates: v })}
        />
      </Row>
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
    <Modal title="设置" onClose={onClose} width={560}>
      <div className="settings-section">外观</div>
      <Row label="主题" hint="深色更适合长时间阅读">
        <Segmented<ThemeMode>
          value={settings.theme}
          onChange={(v) => void update({ theme: v })}
          options={[
            { value: 'light', label: '浅色' },
            { value: 'dark', label: '深色' },
            { value: 'system', label: '跟随系统' }
          ]}
        />
      </Row>
      <Row label="书架卡片大小">
        <Segmented<CardSize>
          value={settings.cardSize}
          onChange={(v) => void update({ cardSize: v })}
          options={[
            { value: 'small', label: '小' },
            { value: 'medium', label: '中' },
            { value: 'large', label: '大' }
          ]}
        />
      </Row>

      <div className="settings-section">阅读</div>
      <Row label="阅读方向" hint="日漫通常为从右到左">
        <Segmented<ReadingDirection>
          value={settings.readingDirection}
          onChange={(v) => void update({ readingDirection: v })}
          options={[
            { value: 'ltr', label: '从左到右' },
            { value: 'rtl', label: '从右到左' }
          ]}
        />
      </Row>
      <Row label="默认阅读模式" hint="每本漫画的调整会单独记住">
        <Segmented<ReadingMode>
          value={settings.defaultMode}
          onChange={(v) => void update({ defaultMode: v })}
          options={[
            { value: 'single', label: '单页' },
            { value: 'double', label: '双页' },
            { value: 'scroll', label: '连续滚动' }
          ]}
        />
      </Row>
      <Row label="默认缩放模式">
        <Segmented<ZoomMode>
          value={settings.defaultZoom}
          onChange={(v) => void update({ defaultZoom: v })}
          options={[
            { value: 'fitWidth', label: '适应宽度' },
            { value: 'fitHeight', label: '适应高度' },
            { value: 'original', label: '原始大小' }
          ]}
        />
      </Row>
      <Row
        label="双页模式：封面单独占屏"
        hint="日漫扫图第一页多为单张封面，之后才两两成对（阅读时按 O 可临时切换）"
      >
        <Toggle
          on={settings.doubleCoverSingle}
          onChange={(v) => void update({ doubleCoverSingle: v })}
        />
      </Row>
      <Row label="双页模式：跨页图铺满整屏" hint="横向的跨页大图不再被塞进半个视口">
        <Toggle on={settings.widePageSpread} onChange={(v) => void update({ widePageSpread: v })} />
      </Row>
      <Row
        label="默认自动裁掉扫描白边"
        hint="扫描版四周的纯色留白会被自动去掉（阅读时按 C 可临时切换）"
      >
        <Toggle on={settings.autoCrop} onChange={(v) => void update({ autoCrop: v })} />
      </Row>
      <Row label="鼠标侧键翻页" hint="鼠标上的后退 / 前进键当作上一页 / 下一页">
        <Toggle
          on={settings.mouseSideButtons}
          onChange={(v) => void update({ mouseSideButtons: v })}
        />
      </Row>
      <Row label="阅读亮度" hint="夜里看白底扫图时调低一点更护眼">
        <div className="settings-range">
          <input
            type="range"
            className="reader-slider"
            min={BRIGHTNESS_MIN}
            max={BRIGHTNESS_MAX}
            step={0.05}
            value={settings.brightness}
            onChange={(e) => void update({ brightness: Number(e.target.value) })}
          />
          <span className="settings-range-value">{Math.round(settings.brightness * 100)}%</span>
        </div>
      </Row>
      <Row label="自动翻页间隔" hint="阅读时按 A 开始 / 停止，[ 与 ] 或底栏滑块可随时调节间隔">
        <div className="settings-range">
          <input
            type="range"
            className="reader-slider"
            min={AUTO_TURN_MIN}
            max={AUTO_TURN_MAX}
            step={1}
            value={settings.autoTurnSeconds}
            onChange={(e) => void update({ autoTurnSeconds: Number(e.target.value) })}
          />
          <span className="settings-range-value">{settings.autoTurnSeconds} 秒</span>
        </div>
      </Row>

      <div className="settings-section">启动</div>
      <Row label="启动时打开上次阅读的漫画">
        <Toggle
          on={settings.openLastOnStartup}
          onChange={(v) => void update({ openLastOnStartup: v })}
        />
      </Row>

      <LibraryRootsSection />
      <DataSection />

      <div className="settings-section">扩展功能</div>
      {EXTENSIONS.map((ext) => (
        <Row key={ext.id} label={ext.name} hint={ext.hint}>
          <Toggle
            on={settings.extensions[ext.id]}
            onChange={(v) => void update({ extensions: { ...settings.extensions, [ext.id]: v } })}
          />
        </Row>
      ))}

      <UpdateSection />
    </Modal>
  )
}
