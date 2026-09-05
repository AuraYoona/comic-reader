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

/** 扩展功能 ID（v3 新增 categories，v4 新增 bookmarks） */
export type ExtensionId = 'categories' | 'bookmarks'

/** 全部扩展功能 ID，供主进程做白名单校验 */
export const EXTENSION_IDS: readonly ExtensionId[] = ['categories', 'bookmarks']

/** 漫画来源类型：本地文件夹 / 文件（ZIP、CBZ、RAR、CBR、PDF） */
export type SourceType = 'folder' | 'archive'

/**
 * 双页模式的配对偏移。
 * 1 = 第一页（封面）单独占屏，之后 (2,3) (4,5) 成对——日漫扫图的常见排布；
 * 0 = 从第一页起 (1,2) (3,4) 成对。
 */
export type PageOffset = 0 | 1

/** 单本漫画的阅读偏好（覆盖全局默认值，字段缺省时回退到全局设置） */
export interface ComicReaderPrefs {
  mode?: ReadingMode
  zoom?: ZoomMode
  /** 在缩放模式基础上的倍率，1 = 100% */
  zoomScale?: number
  direction?: ReadingDirection
  /** 双页配对偏移（v4 新增），缺省时取全局 doubleCoverSingle */
  pageOffset?: PageOffset
  /** 自动裁掉扫描留下的白边（v4 新增），缺省时取全局 autoCrop */
  autoCrop?: boolean
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
  /** 所属分类 id 列表（v3 新增，一本漫画可属于多个分类） */
  categoryIds: string[]
  /** 书签页码，0 起始、升序去重（v4 新增，属于「书签」扩展功能） */
  bookmarks: number[]
}

/** 自定义分类（v3 新增，属于「自定义分类」扩展功能） */
export interface Category {
  id: string
  name: string
  /** 预设调色板中的颜色，形如 #rrggbb */
  color: string
  createdAt: number
}

/** 分类可选颜色，新建时按已有数量循环取默认值 */
export const CATEGORY_COLORS: readonly string[] = [
  '#ef4444',
  '#f97316',
  '#eab308',
  '#22c55e',
  '#14b8a6',
  '#3b82f6',
  '#8b5cf6',
  '#ec4899'
]

/** 分类名称最大长度 */
export const CATEGORY_NAME_MAX = 20

/** 漫画标题最大长度 */
export const TITLE_MAX = 120

/** 记住的漫画库根目录数量上限 */
export const LIBRARY_ROOTS_MAX = 20

/** 新建/修改分类的结果 */
export interface CategoryMutationResult {
  ok: boolean
  category?: Category
  error?: string
}

/** 修改分类的补丁 */
export interface CategoryPatch {
  name?: string
  color?: string
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
  /** 扩展功能开关（v3 新增），关闭只隐藏入口，不删除任何数据 */
  extensions: Record<ExtensionId, boolean>
  /** 启动时自动检查更新（仅打包后的安装版生效） */
  autoCheckUpdates: boolean

  // ---- v4 新增 ----
  /** 双页模式默认让第一页（封面）单独占屏 */
  doubleCoverSingle: boolean
  /** 双页模式下把横向跨页图铺满整屏，不塞进半个视口 */
  widePageSpread: boolean
  /** 阅读器亮度滤镜，1 = 原始亮度 */
  brightness: number
  /** 自动翻页间隔（秒） */
  autoTurnSeconds: number
  /** 鼠标侧键（后退 / 前进键）翻页 */
  mouseSideButtons: boolean
  /** 默认自动裁掉扫描白边 */
  autoCrop: boolean
  /** 漫画库根目录，批量导入时自动记录 */
  libraryRoots: string[]
  /** 启动时扫描库根目录，把新增的漫画自动上架 */
  autoScanRoots: boolean
}

export const DEFAULT_SETTINGS: AppSettings = {
  theme: 'system',
  readingDirection: 'ltr',
  defaultMode: 'single',
  defaultZoom: 'fitWidth',
  openLastOnStartup: false,
  lastOpenedComicId: null,
  cardSize: 'medium',
  extensions: { categories: false, bookmarks: false },
  autoCheckUpdates: true,
  doubleCoverSingle: true,
  widePageSpread: true,
  brightness: 1,
  autoTurnSeconds: 6,
  mouseSideButtons: true,
  autoCrop: false,
  libraryRoots: [],
  autoScanRoots: true
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

/** 重命名结果 */
export interface RenameResult {
  ok: boolean
  comic?: Comic
  error?: string
}

/** 批量重新扫描的结果 */
export interface BatchRescanResult {
  updated: Comic[]
  failed: { id: string; title: string; error: string }[]
}

/** 来源路径批量重定位的结果 */
export interface RelocateResult {
  /** 用户取消了目录选择 */
  canceled: boolean
  /** 选中的新根目录 */
  root?: string
  /** 成功改绑的记录 */
  relocated: Comic[]
  /** 在新根目录下没找到对应文件的数量 */
  unmatched: number
  error?: string
}

/** 数据导出结果 */
export interface BackupResult {
  canceled: boolean
  ok: boolean
  /** 备份目录的完整路径 */
  path?: string
  comics?: number
  covers?: number
  error?: string
}

/** 数据导入模式：合并（跳过已存在的来源）/ 覆盖（整库替换） */
export type RestoreMode = 'merge' | 'replace'

/** 数据导入结果 */
export interface RestoreResult {
  canceled: boolean
  ok: boolean
  mode?: RestoreMode
  imported?: number
  skipped?: number
  error?: string
}

/** 库根目录扫描结果 */
export interface ScanRootsResult {
  /** 扫描过的根目录数量 */
  roots: number
  /** 自动上架的新漫画 */
  added: Comic[]
  /** 读不了的根目录 */
  unreadable: string[]
}

export const ZOOM_SCALE_MIN = 0.25
export const ZOOM_SCALE_MAX = 4

export function clampZoomScale(v: number): number {
  return Math.min(ZOOM_SCALE_MAX, Math.max(ZOOM_SCALE_MIN, Math.round(v * 100) / 100))
}

export const BRIGHTNESS_MIN = 0.3
export const BRIGHTNESS_MAX = 1.2

/** 亮度滤镜倍率，步进 0.05 */
export function clampBrightness(v: number): number {
  if (!Number.isFinite(v)) return 1
  return Math.min(BRIGHTNESS_MAX, Math.max(BRIGHTNESS_MIN, Math.round(v * 20) / 20))
}

export const AUTO_TURN_MIN = 2
export const AUTO_TURN_MAX = 60

/** 自动翻页间隔（整数秒） */
export function clampAutoTurnSeconds(v: number): number {
  if (!Number.isFinite(v)) return DEFAULT_SETTINGS.autoTurnSeconds
  return Math.min(AUTO_TURN_MAX, Math.max(AUTO_TURN_MIN, Math.round(v)))
}
