/** IPC 通道名统一定义，主进程与预加载脚本共用，避免字符串散落各处 */
export const IPC = {
  /** invoke: 弹出系统对话框选择文件夹/压缩包并导入 */
  ImportSelect: 'import:select',
  /** invoke: 导入指定路径（拖拽用） */
  ImportPaths: 'import:paths',
  /** event(main→renderer): 导入进度 { current, total, path } */
  ImportProgress: 'import:progress',

  LibraryGet: 'library:get',
  LibraryRemove: 'library:remove',
  LibraryUpdateProgress: 'library:update-progress',
  /** invoke: 批量检查来源文件是否还存在 */
  LibraryVerify: 'library:verify',

  SettingsGet: 'settings:get',
  SettingsSave: 'settings:save',

  /** invoke: 打开漫画，重新扫描来源并返回最新页数 */
  ComicOpen: 'comic:open',
  ComicReveal: 'comic:reveal',
  /** invoke: 重新扫描单本（刷新页数、重新生成封面） */
  ComicRescan: 'comic:rescan',

  WindowSetFullscreen: 'window:set-fullscreen',
  WindowIsFullscreen: 'window:is-fullscreen',
  /** event(main→renderer): 全屏状态变化 */
  WindowFullscreenChanged: 'window:fullscreen-changed'
} as const

export type IpcChannel = (typeof IPC)[keyof typeof IPC]
