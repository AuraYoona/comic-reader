import fs from 'node:fs'
import path from 'node:path'
import { app } from 'electron'
import {
  DEFAULT_SETTINGS,
  type AppSettings,
  type Comic,
  type ComicReaderPrefs
} from '@shared/types'
import { logger } from '../lib/logger'
import { CURRENT_SCHEMA_VERSION, migrateLibraryData } from './migrations'

interface LibraryFile {
  version: number
  settings: AppSettings
  comics: Comic[]
}

const SAVE_DEBOUNCE_MS = 400

function emptyLibrary(): LibraryFile {
  return { version: CURRENT_SCHEMA_VERSION, settings: { ...DEFAULT_SETTINGS }, comics: [] }
}

/** 过滤掉非法设置值（例如手改 JSON 写错枚举），保证运行时值总是可用 */
function sanitizeSettings(raw: unknown): AppSettings {
  const s = { ...DEFAULT_SETTINGS }
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
  return s
}

function sanitizeComics(raw: unknown): Comic[] {
  if (!Array.isArray(raw)) return []
  return raw.filter(
    (c): c is Comic =>
      !!c &&
      typeof c === 'object' &&
      typeof (c as Comic).id === 'string' &&
      typeof (c as Comic).sourcePath === 'string' &&
      typeof (c as Comic).title === 'string'
  )
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
      logger.warn(
        'db',
        `数据版本 v${fromVersion} 高于当前支持的 v${CURRENT_SCHEMA_VERSION}（可能安装了旧版应用），按兼容模式读取`
      )
    }

    this.data = {
      version: CURRENT_SCHEMA_VERSION,
      settings: sanitizeSettings(data.settings),
      comics: sanitizeComics(data.comics)
    }

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
