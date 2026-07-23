import type {
  AppSettings,
  Category,
  CategoryMutationResult,
  CategoryPatch,
  Comic,
  ImportResult,
  OpenComicResult,
  ProgressPatch,
  SourceCheck
} from './types'

/** 导入进度事件负载 */
export interface ImportProgress {
  current: number
  total: number
  path: string
}

/** 导入入口：文件夹 / 压缩包 / 批量（选一个根目录，每个子文件夹或压缩包算一本） */
export type ImportKind = 'folder' | 'archive' | 'batch'

/** 更新状态事件（主进程 → 渲染进程） */
export type UpdateEvent =
  | { type: 'checking' }
  | { type: 'available'; version: string }
  | { type: 'not-available' }
  | { type: 'downloading'; percent: number }
  | { type: 'downloaded'; version: string }
  | { type: 'error'; message: string }

/**
 * 预加载脚本暴露给渲染进程的 API（window.api）。
 * 预加载实现它，渲染进程只依赖这个类型。
 */
export interface RendererApi {
  importSelect(kind: ImportKind): Promise<ImportResult[]>
  importPaths(paths: string[]): Promise<ImportResult[]>
  onImportProgress(cb: (p: ImportProgress) => void): () => void

  getLibrary(): Promise<Comic[]>
  removeComic(id: string): Promise<void>
  updateProgress(id: string, patch: ProgressPatch): Promise<Comic | null>
  /** 批量检查来源是否仍然存在（书架“来源丢失”徽标） */
  verifyLibrary(): Promise<SourceCheck[]>

  openComic(id: string): Promise<OpenComicResult>
  revealComic(id: string): Promise<void>
  /** 重新扫描：刷新页数并重新生成封面 */
  rescanComic(id: string): Promise<OpenComicResult>

  getSettings(): Promise<AppSettings>
  saveSettings(patch: Partial<AppSettings>): Promise<AppSettings>

  /** 「自定义分类」扩展功能：列出全部分类（按创建时间升序） */
  listCategories(): Promise<Category[]>
  createCategory(name: string, color?: string): Promise<CategoryMutationResult>
  updateCategory(id: string, patch: CategoryPatch): Promise<CategoryMutationResult>
  /** 删除分类并解除所有漫画与它的关联，返回是否删除成功 */
  deleteCategory(id: string): Promise<boolean>
  /** 把漫画加入/移出一个分类，方向由主进程按当前归属判定（并发切换不会互相覆盖），返回更新后的记录 */
  toggleComicCategory(id: string, categoryId: string): Promise<Comic | null>

  setFullscreen(flag: boolean): Promise<void>
  isFullscreen(): Promise<boolean>
  onFullscreenChange(cb: (fs: boolean) => void): () => void

  /** 立即检查更新；开发模式或便携版下返回 false 表示不可用 */
  checkForUpdates(): Promise<boolean>
  /** 下载已发现的新版本，进度通过 onUpdateEvent 推送 */
  downloadUpdate(): Promise<void>
  /** 退出并安装已下载的更新 */
  installUpdate(): Promise<void>
  getAppVersion(): Promise<string>
  onUpdateEvent(cb: (e: UpdateEvent) => void): () => void

  /** 拖拽导入时把 File 对象换成磁盘路径 */
  pathForFile(file: File): string
}
