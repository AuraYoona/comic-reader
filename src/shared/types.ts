/** 阅读模式：单页 / 双页 / 连续滚动 */
export type ReadingMode = 'single' | 'double' | 'scroll'

/** 缩放模式：适应宽度 / 适应高度 / 原始大小 */
export type ZoomMode = 'fitWidth' | 'fitHeight' | 'original'

/** 阅读方向：从左到右 / 从右到左（日漫习惯） */
export type ReadingDirection = 'ltr' | 'rtl'

/** 主题 */
export type ThemeMode = 'light' | 'dark' | 'system'

/** 书架排序字段 */
export type SortKey = 'title' | 'lastReadAt' | 'addedAt'

/** 书架卡片大小 */
export type CardSize = 'small' | 'medium' | 'large'

/** 漫画来源类型：本地文件夹 / ZIP、CBZ 压缩包 */
export type SourceType = 'folder' | 'archive'

/** 单本漫画的阅读偏好（覆盖全局默认值，字段缺省时回退到全局设置） */
export interface ComicReaderPrefs {
  mode?: ReadingMode
  zoom?: ZoomMode
  /** 在缩放模式基础上的倍率，1 = 100% */
  zoomScale?: number
  direction?: ReadingDirection
}

/** 书架中的一本漫画 */
export interface Comic {
  id: string
  title: string
  sourceType: SourceType
  /** 原始文件/文件夹的绝对路径，删除条目时不会删除它 */
  sourcePath: string
  pageCount: number
  /** 封面文件名（位于 userData/covers 下），生成失败时为 null */
  coverFile: string | null
  addedAt: number
  lastReadAt: number | null
  /** 0 起始的页码 */
  lastReadPage: number
  reader: ComicReaderPrefs
}

/** 全局设置 */
export interface AppSettings {
  theme: ThemeMode
  readingDirection: ReadingDirection
  defaultMode: ReadingMode
  defaultZoom: ZoomMode
  /** 启动时自动打开上次阅读的漫画 */
  openLastOnStartup: boolean
  lastOpenedComicId: string | null
  /** 书架卡片大小（v2 新增） */
  cardSize: CardSize
}

export const DEFAULT_SETTINGS: AppSettings = {
  theme: 'system',
  readingDirection: 'ltr',
  defaultMode: 'single',
  defaultZoom: 'fitWidth',
  openLastOnStartup: false,
  lastOpenedComicId: null,
  cardSize: 'medium'
}

/** 单个导入项的结果 */
export interface ImportResult {
  path: string
  status: 'imported' | 'skipped' | 'failed'
  comic?: Comic
  reason?: string
}

/** 打开漫画（进入阅读器）的结果，主进程会重新扫描来源 */
export interface OpenComicResult {
  ok: boolean
  comic?: Comic
  pageCount?: number
  error?: string
}

/** 渲染进程上报的进度补丁 */
export interface ProgressPatch {
  lastReadPage?: number
  reader?: ComicReaderPrefs
}

/** 来源存在性校验结果 */
export interface SourceCheck {
  id: string
  missing: boolean
}

export const ZOOM_SCALE_MIN = 0.25
export const ZOOM_SCALE_MAX = 4

export function clampZoomScale(v: number): number {
  return Math.min(ZOOM_SCALE_MAX, Math.max(ZOOM_SCALE_MIN, Math.round(v * 100) / 100))
}
