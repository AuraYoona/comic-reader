/** IPC 通道名统一定义，主进程与预加载脚本共用，避免字符串散落各处 */
export const IPC = {
  /** invoke: 弹出系统对话框选择文件夹 / 压缩包 / PDF 并导入 */
  ImportSelect: 'import:select',
  /** invoke: 导入指定路径（拖拽用） */
  ImportPaths: 'import:paths',
  /** event(main→renderer): 导入进度 { current, total, path } */
  ImportProgress: 'import:progress',

  LibraryGet: 'library:get',
  LibraryRemove: 'library:remove',
  /** invoke: 批量移除，返回真正被移除的 id */
  LibraryRemoveMany: 'library:remove-many',
  LibraryUpdateProgress: 'library:update-progress',
  /** invoke: 批量检查来源文件是否还存在 */
  LibraryVerify: 'library:verify',
  /** invoke: 重命名书架标题 */
  LibraryRename: 'library:rename',
  /** invoke: 选新根目录批量改绑来源路径（整库搬盘后用） */
  LibraryRelocate: 'library:relocate',
  /** invoke: 把书架数据与封面导出到用户选择的文件夹 */
  LibraryBackup: 'library:backup',
  /** invoke: 从备份文件夹恢复（合并 / 覆盖） */
  LibraryRestore: 'library:restore',
  /** invoke: 扫描已记录的库根目录，自动上架新增漫画 */
  LibraryScanRoots: 'library:scan-roots',
  /** invoke: 选择一个库根目录加入监视列表，返回更新后的设置 */
  LibraryAddRoot: 'library:add-root',

  SettingsGet: 'settings:get',
  SettingsSave: 'settings:save',

  /** invoke: 分类列表（「自定义分类」扩展功能） */
  CategoryList: 'category:list',
  CategoryCreate: 'category:create',
  CategoryUpdate: 'category:update',
  /** invoke: 删除分类，仅解除漫画与它的关联，不影响漫画本身 */
  CategoryDelete: 'category:delete',

  /** invoke: 打开漫画，重新扫描来源并返回最新页数 */
  ComicOpen: 'comic:open',
  ComicReveal: 'comic:reveal',
  /** invoke: 重新扫描单本（刷新页数、重新生成封面） */
  ComicRescan: 'comic:rescan',
  /** invoke: 批量重新扫描 */
  ComicRescanMany: 'comic:rescan-many',
  /** invoke: 把漫画加入/移出一个分类（主进程按当前归属决定方向） */
  ComicToggleCategory: 'comic:toggle-category',
  /** invoke: 把多本漫画统一加入/移出一个分类 */
  ComicToggleCategoryMany: 'comic:toggle-category-many',
  /** invoke: 增删一个书签页（「书签」扩展功能） */
  ComicToggleBookmark: 'comic:toggle-bookmark',

  /** invoke: 渲染进程回传重新压缩过的封面 JPEG（nativeImage 解不了 WebP/AVIF 等格式） */
  CoverSaveThumb: 'cover:save-thumb',

  /** invoke: 立即检查更新（返回是否发起了检查，开发模式下不可用） */
  UpdateCheck: 'update:check',
  /** invoke: 开始下载已发现的新版本 */
  UpdateDownload: 'update:download',
  /** invoke: 退出并安装已下载的更新 */
  UpdateInstall: 'update:install',
  /** invoke: 当前应用版本号 */
  UpdateGetVersion: 'update:get-version',
  /** event(main→renderer): 更新状态推送（检查中/有新版本/下载进度/下载完成/出错） */
  UpdateEvent: 'update:event',

  WindowSetFullscreen: 'window:set-fullscreen',
  WindowIsFullscreen: 'window:is-fullscreen',
  /** event(main→renderer): 全屏状态变化 */
  WindowFullscreenChanged: 'window:fullscreen-changed'
} as const

export type IpcChannel = (typeof IPC)[keyof typeof IPC]
