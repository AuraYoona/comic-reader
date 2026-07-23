import fs from 'node:fs'
import { randomUUID } from 'node:crypto'
import path from 'node:path'
import { app } from 'electron'
import {
  CATEGORY_COLORS,
  DEFAULT_SETTINGS,
  EXTENSION_IDS,
  type AppSettings,
  type Category,
  type CategoryPatch,
  type Comic,
  type ComicReaderPrefs
} from '@shared/types'
import { logger } from '../lib/logger'
import { CURRENT_SCHEMA_VERSION, migrateLibraryData } from './migrations'

interface LibraryFile {
  version: number
  settings: AppSettings
  comics: Comic[]
  categories: Category[]
}

const SAVE_DEBOUNCE_MS = 400

/** 分类颜色必须是 #rrggbb 形式，非法值回退到预设色 */
const HEX_COLOR_RE = /^#[0-9a-f]{6}$/i

function emptyLibrary(): LibraryFile {
  return {
    version: CURRENT_SCHEMA_VERSION,
    // extensions 要单独浅拷贝：直接展开会与 DEFAULT_SETTINGS 共享同一个对象，改写时污染常量
    settings: { ...DEFAULT_SETTINGS, extensions: { ...DEFAULT_SETTINGS.extensions } },
    comics: [],
    categories: []
  }
}

/** 过滤掉非法设置值（例如手改 JSON 写错枚举），保证运行时值总是可用 */
function sanitizeSettings(raw: unknown): AppSettings {
  const s = { ...DEFAULT_SETTINGS, extensions: { ...DEFAULT_SETTINGS.extensions } }
  if (!raw || typeof raw !== 'object') return s
  const r = raw as Record<string, unknown>
  if (r.theme === 'light' || r.theme === 'dark' || r.theme === 'system') s.theme = r.theme
  if (r.readingDirection === 'ltr' || r.readingDirection === 'rtl')
    s.readingDirection = r.readingDirection
  if (r.defaultMode === 'single' || r.defaultMode === 'double' || r.defaultMode === 'scroll')
    s.defaultMode = r.defaultMode
  if (r.defaultZoom === 'fitWidth' || r.defaultZoom === 'fitHeight' || r.defaultZoom === 'original')
    s.defaultZoom = r.defaultZoom
  if (typeof r.openLastOnStartup === 'boolean') s.openLastOnStartup = r.openLastOnStartup
  if (typeof r.lastOpenedComicId === 'string') s.lastOpenedComicId = r.lastOpenedComicId
  if (r.cardSize === 'small' || r.cardSize === 'medium' || r.cardSize === 'large')
    s.cardSize = r.cardSize
  if (typeof r.autoCheckUpdates === 'boolean') s.autoCheckUpdates = r.autoCheckUpdates
  if (r.extensions && typeof r.extensions === 'object') {
    const ext = r.extensions as Record<string, unknown>
    // 只认白名单里的扩展 ID，且值必须是布尔
    for (const id of EXTENSION_IDS) {
      if (typeof ext[id] === 'boolean') s.extensions[id] = ext[id]
    }
  }
  return s
}

function sanitizeComics(raw: unknown): Comic[] {
  if (!Array.isArray(raw)) return []
  return raw
    .filter(
      (c): c is Comic =>
        !!c &&
        typeof c === 'object' &&
        typeof (c as Comic).id === 'string' &&
        typeof (c as Comic).sourcePath === 'string' &&
        typeof (c as Comic).title === 'string'
    )
    .map((c) => ({
      ...c,
      // categoryIds 必须存在且元素都是字符串，其余字段原样透传
      categoryIds: Array.isArray(c.categoryIds)
        ? c.categoryIds.filter((id) => typeof id === 'string')
        : []
    }))
}

/** 过滤非法分类记录：id/name 必须是字符串且 name 去空白后非空，按 id 去重 */
function sanitizeCategories(raw: unknown): Category[] {
  if (!Array.isArray(raw)) return []
  const out: Category[] = []
  const seen = new Set<string>()
  for (const item of raw) {
    if (!item || typeof item !== 'object') continue
    const r = item as Record<string, unknown>
    if (typeof r.id !== 'string' || typeof r.name !== 'string') continue
    const name = r.name.trim()
    if (!name || seen.has(r.id)) continue
    seen.add(r.id)
    out.push({
      id: r.id,
      name,
      color:
        typeof r.color === 'string' && HEX_COLOR_RE.test(r.color)
          ? r.color
          : CATEGORY_COLORS[out.length % CATEGORY_COLORS.length],
      createdAt: typeof r.createdAt === 'number' ? r.createdAt : Date.now()
    })
  }
  return out
}

/**
 * 基于单个 JSON 文件的本地数据库。
 * - 内存即时更新 + 防抖落盘；「写临时文件再改名」保证原子性；退出时同步 flush
 * - 加载时经过 migrations 管线逐级升级，迁移前把原文件备份为 library.json.v<N>.bak
 * - 解析失败时备份损坏文件并从空库启动，绝不让应用起不来
 */
class Database {
  private filePath = ''
  private data: LibraryFile = emptyLibrary()
  private saveTimer: NodeJS.Timeout | null = null
  private dirty = false

  init(): void {
    const dir = app.getPath('userData')
    this.filePath = path.join(dir, 'library.json')
    fs.mkdirSync(this.coversDir(), { recursive: true })
    this.load()
  }

  coversDir(): string {
    return path.join(app.getPath('userData'), 'covers')
  }

  private load(): void {
    if (!fs.existsSync(this.filePath)) {
      this.data = emptyLibrary()
      return
    }

    let rawText: string
    try {
      rawText = fs.readFileSync(this.filePath, 'utf-8')
    } catch (err) {
      logger.error('db', '读取 library.json 失败，使用空库启动', err)
      this.data = emptyLibrary()
      return
    }

    let parsed: unknown
    try {
      parsed = JSON.parse(rawText)
    } catch (err) {
      const backup = `${this.filePath}.corrupt-${Date.now()}`
      try {
        fs.writeFileSync(backup, rawText, 'utf-8')
      } catch {
        /* 备份失败也继续 */
      }
      logger.error('db', `library.json 解析失败，已备份到 ${backup}`, err)
      this.data = emptyLibrary()
      return
    }

    const { data, fromVersion, migrated } = migrateLibraryData(parsed)
    if (migrated) {
      const backup = `${this.filePath}.v${fromVersion}.bak`
      try {
        fs.writeFileSync(backup, rawText, 'utf-8')
      } catch (err) {
        logger.warn('db', '迁移前备份失败（继续迁移）', err)
      }
      logger.info(
        'db',
        `数据结构从 v${fromVersion} 迁移到 v${CURRENT_SCHEMA_VERSION}，原文件已备份为 ${path.basename(backup)}`
      )
    }
    if (fromVersion > CURRENT_SCHEMA_VERSION) {
      // 本版本一旦写盘就会丢掉未知的新字段，先做一次性备份（保留最早那份）以便回滚后恢复
      const backup = `${this.filePath}.v${fromVersion}.bak`
      try {
        if (!fs.existsSync(backup)) fs.writeFileSync(backup, rawText, 'utf-8')
      } catch (err) {
        logger.warn('db', '高版本数据备份失败（继续按兼容模式读取）', err)
      }
      logger.warn(
        'db',
        `数据版本 v${fromVersion} 高于当前支持的 v${CURRENT_SCHEMA_VERSION}（可能安装了旧版应用），按兼容模式读取`
      )
    }

    const settings = sanitizeSettings(data.settings)
    const comics = sanitizeComics(data.comics)
    const categories = sanitizeCategories(data.categories)
    // 分类记录可能在上面被过滤掉，同步剥离漫画里指向它们的悬空 id
    const knownIds = new Set(categories.map((c) => c.id))
    for (const comic of comics) {
      if (comic.categoryIds.some((cid) => !knownIds.has(cid))) {
        comic.categoryIds = comic.categoryIds.filter((cid) => knownIds.has(cid))
      }
    }
    this.data = { version: CURRENT_SCHEMA_VERSION, settings, comics, categories }

    if (migrated) {
      this.dirty = true
      this.writeToDisk()
    }
  }

  // ---------- 漫画 ----------

  listComics(): Comic[] {
    return this.data.comics
  }

  getComic(id: string): Comic | undefined {
    return this.data.comics.find((c) => c.id === id)
  }

  upsertComic(comic: Comic): void {
    const idx = this.data.comics.findIndex((c) => c.id === comic.id)
    if (idx >= 0) this.data.comics[idx] = comic
    else this.data.comics.push(comic)
    this.saveSoon()
  }

  updateComic(
    id: string,
    patch: Partial<Omit<Comic, 'reader'>> & { reader?: ComicReaderPrefs }
  ): Comic | null {
    const comic = this.getComic(id)
    if (!comic) return null
    const { reader, ...rest } = patch
    Object.assign(comic, rest)
    if (reader) comic.reader = { ...comic.reader, ...reader }
    this.saveSoon()
    return comic
  }

  removeComic(id: string): void {
    this.data.comics = this.data.comics.filter((c) => c.id !== id)
    if (this.data.settings.lastOpenedComicId === id) {
      this.data.settings.lastOpenedComicId = null
    }
    this.saveSoon()
  }

  // ---------- 设置 ----------

  getSettings(): AppSettings {
    return this.data.settings
  }

  saveSettings(patch: Partial<AppSettings>): AppSettings {
    this.data.settings = sanitizeSettings({ ...this.data.settings, ...patch })
    this.saveSoon()
    return this.data.settings
  }

  // ---------- 分类 ----------

  listCategories(): Category[] {
    return this.data.categories
  }

  createCategory(name: string, color?: string): Category {
    const category: Category = {
      id: randomUUID(),
      // 名称合法性由 IPC 层校验，这里只做兜底 trim
      name: name.trim(),
      color:
        color && HEX_COLOR_RE.test(color)
          ? color
          : CATEGORY_COLORS[this.data.categories.length % CATEGORY_COLORS.length],
      createdAt: Date.now()
    }
    this.data.categories.push(category)
    this.saveSoon()
    return category
  }

  updateCategory(id: string, patch: CategoryPatch): Category | null {
    const category = this.data.categories.find((c) => c.id === id)
    if (!category) return null
    if (typeof patch.name === 'string') category.name = patch.name.trim()
    if (typeof patch.color === 'string' && HEX_COLOR_RE.test(patch.color)) {
      category.color = patch.color
    }
    this.saveSoon()
    return category
  }

  /** 删除分类只解除漫画与它的关联，不影响漫画记录本身 */
  deleteCategory(id: string): boolean {
    const before = this.data.categories.length
    this.data.categories = this.data.categories.filter((c) => c.id !== id)
    if (this.data.categories.length === before) return false
    for (const comic of this.data.comics) {
      if (comic.categoryIds.includes(id)) {
        comic.categoryIds = comic.categoryIds.filter((cid) => cid !== id)
      }
    }
    this.saveSoon()
    return true
  }

  /** 把漫画加入/移出一个分类：按主进程当前归属决定方向，渲染进程的过期快照不会互相覆盖 */
  toggleComicCategory(id: string, categoryId: string): Comic | null {
    const comic = this.getComic(id)
    if (!comic) return null
    // 分类已不存在（可能刚被删除）时不变更；删除分类时已剥离过关联
    if (!this.data.categories.some((c) => c.id === categoryId)) return comic
    comic.categoryIds = comic.categoryIds.includes(categoryId)
      ? comic.categoryIds.filter((cid) => cid !== categoryId)
      : [...comic.categoryIds, categoryId]
    this.saveSoon()
    return comic
  }

  // ---------- 落盘 ----------

  private saveSoon(): void {
    this.dirty = true
    if (this.saveTimer) clearTimeout(this.saveTimer)
    this.saveTimer = setTimeout(() => {
      this.saveTimer = null
      this.writeToDisk()
    }, SAVE_DEBOUNCE_MS)
  }

  private writeToDisk(): void {
    if (!this.dirty || !this.filePath) return
    try {
      const tmp = `${this.filePath}.tmp`
      fs.writeFileSync(tmp, JSON.stringify(this.data, null, 2), 'utf-8')
      fs.renameSync(tmp, this.filePath)
      this.dirty = false
    } catch (err) {
      logger.error('db', '保存 library.json 失败', err)
    }
  }

  /** 应用退出前同步写盘 */
  flushSync(): void {
    if (this.saveTimer) {
      clearTimeout(this.saveTimer)
      this.saveTimer = null
    }
    this.writeToDisk()
  }
}

export const db = new Database()
