import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

/** electron 的 app.getPath 指到临时目录，每个用例一份干净的 userData */
const env = vi.hoisted(() => ({ userData: '' }))

vi.mock('electron', () => ({ app: { getPath: () => env.userData } }))
vi.mock('../../src/main/lib/logger', () => ({
  logger: { info: () => {}, warn: () => {}, error: () => {} }
}))

const { db, normalizeLibraryData, sanitizeBookmarks } = await import('../../src/main/store/db')
const { CURRENT_SCHEMA_VERSION } = await import('../../src/main/store/migrations')

const libraryPath = (): string => path.join(env.userData, 'library.json')
const readLibraryText = (): string => fs.readFileSync(libraryPath(), 'utf-8')
const readLibrary = (): Record<string, any> => JSON.parse(readLibraryText())

function makeComic(id: string, over: Record<string, unknown> = {}): any {
  return {
    id,
    title: `漫画 ${id}`,
    sourceType: 'folder',
    sourcePath: `D:/comics/${id}`,
    pageCount: 20,
    coverFile: `${id}.jpg`,
    addedAt: 1000,
    lastReadAt: null,
    lastReadPage: 0,
    reader: {},
    categoryIds: [],
    bookmarks: [],
    ...over
  }
}

/** 预置一份磁盘上的 library.json，然后 init */
function seed(data: unknown): void {
  fs.writeFileSync(libraryPath(), JSON.stringify(data), 'utf-8')
  db.init()
}

beforeEach(() => {
  env.userData = fs.mkdtempSync(path.join(os.tmpdir(), 'comic-reader-test-'))
})

afterEach(() => {
  db.flushSync()
  fs.rmSync(env.userData, { recursive: true, force: true })
})

describe('初始化', () => {
  it('没有数据文件时以空库启动，并建好 covers 目录', () => {
    db.init()
    expect(db.listComics()).toEqual([])
    expect(db.listCategories()).toEqual([])
    expect(db.getSettings().theme).toBe('system')
    expect(fs.existsSync(db.coversDir())).toBe(true)
  })

  it('默认设置不共享同一个 extensions 对象（改一个库不会污染常量）', () => {
    db.init()
    db.saveSettings({ extensions: { categories: true, bookmarks: false } })
    const first = db.getSettings().extensions.categories
    // 换一个全新的 userData 再来一次，应当回到默认值
    env.userData = fs.mkdtempSync(path.join(os.tmpdir(), 'comic-reader-test-'))
    db.init()
    expect(first).toBe(true)
    expect(db.getSettings().extensions.categories).toBe(false)
  })
})

describe('迁移与自愈', () => {
  it('v3 数据自动升到当前版本，并留下迁移前的备份', () => {
    seed({
      version: 3,
      settings: { theme: 'dark', extensions: { categories: true } },
      categories: [],
      comics: [{ id: 'a', title: 'A', sourcePath: 'D:/a', categoryIds: [] }]
    })
    expect(db.listComics()[0].bookmarks).toEqual([])
    expect(db.getSettings().extensions).toEqual({ categories: true, bookmarks: false })
    expect(db.getSettings().theme).toBe('dark')
    expect(readLibrary().version).toBe(CURRENT_SCHEMA_VERSION)
    expect(fs.existsSync(`${libraryPath()}.v3.bak`)).toBe(true)
  })

  it('文件损坏时备份原文件并以空库启动，不让应用起不来', () => {
    fs.writeFileSync(libraryPath(), '{ 这不是 JSON', 'utf-8')
    db.init()
    expect(db.listComics()).toEqual([])
    const backups = fs.readdirSync(env.userData).filter((f) => f.includes('.corrupt-'))
    expect(backups).toHaveLength(1)
  })

  it('高版本数据按兼容模式读取，不降级改写', () => {
    seed({
      version: CURRENT_SCHEMA_VERSION + 3,
      settings: { theme: 'dark' },
      comics: [makeComic('a')],
      categories: []
    })
    expect(db.getSettings().theme).toBe('dark')
    expect(db.listComics()).toHaveLength(1)
    expect(fs.existsSync(`${libraryPath()}.v${CURRENT_SCHEMA_VERSION + 3}.bak`)).toBe(true)
  })

  it('丢弃结构非法的记录，并剥离指向不存在分类的悬空 id', () => {
    seed({
      version: CURRENT_SCHEMA_VERSION,
      settings: {},
      categories: [{ id: 'c1', name: '连载中', color: '#ef4444', createdAt: 1 }],
      comics: [
        makeComic('a', { categoryIds: ['c1', '幽灵分类'] }),
        { id: 'b' }, // 缺 title / sourcePath
        null
      ]
    })
    expect(db.listComics().map((c) => c.id)).toEqual(['a'])
    expect(db.listComics()[0].categoryIds).toEqual(['c1'])
  })
})

describe('设置清洗', () => {
  it('非法枚举与越界数值回落到默认', () => {
    seed({
      version: CURRENT_SCHEMA_VERSION,
      settings: {
        theme: '荧光粉',
        cardSize: 'huge',
        brightness: 99,
        autoTurnSeconds: 0,
        extensions: { categories: 'yes', 不存在的扩展: true }
      },
      comics: [],
      categories: []
    })
    const s = db.getSettings()
    expect(s.theme).toBe('system')
    expect(s.cardSize).toBe('medium')
    expect(s.brightness).toBe(1.2) // 夹到上限
    expect(s.autoTurnSeconds).toBe(2) // 夹到下限
    expect(s.extensions).toEqual({ categories: false, bookmarks: false })
    expect('不存在的扩展' in s.extensions).toBe(false)
  })

  it('库根目录去重（Windows 下不分大小写）并有数量上限', () => {
    db.init()
    const many = Array.from({ length: 30 }, (_, i) => `D:/lib${i}`)
    const s = db.saveSettings({ libraryRoots: ['D:/A', 'd:/a', ...many, ''] })
    expect(s.libraryRoots).toHaveLength(20)
    expect(s.libraryRoots[0]).toBe('D:/A')
    expect(s.libraryRoots[1]).toBe('D:/lib0')
  })

  it('addLibraryRoot 幂等', () => {
    db.init()
    db.addLibraryRoot('D:/漫画')
    db.addLibraryRoot('D:/漫画')
    expect(db.getSettings().libraryRoots).toEqual(['D:/漫画'])
  })
})

describe('漫画记录', () => {
  beforeEach(() => {
    db.init()
    db.upsertComic(makeComic('a'))
    db.upsertComic(makeComic('b'))
    db.upsertComic(makeComic('c'))
  })

  it('批量移除只删掉存在的记录，并清掉 lastOpenedComicId', () => {
    db.saveSettings({ lastOpenedComicId: 'b' })
    const removed = db.removeComics(['b', 'c', '不存在'])
    expect(removed.sort()).toEqual(['b', 'c'])
    expect(db.listComics().map((c) => c.id)).toEqual(['a'])
    expect(db.getSettings().lastOpenedComicId).toBeNull()
  })

  it('重命名会 trim 并截断超长标题', () => {
    expect(db.renameComic('a', '  新名字  ')?.title).toBe('新名字')
    const long = 'x'.repeat(500)
    expect(db.renameComic('a', long)?.title).toHaveLength(120)
    expect(db.renameComic('不存在', 'x')).toBeNull()
  })

  it('改绑来源路径不动其它字段', () => {
    db.updateComic('a', { lastReadPage: 7 })
    const moved = db.setSourcePath('a', 'E:/comics/a')
    expect(moved?.sourcePath).toBe('E:/comics/a')
    expect(moved?.lastReadPage).toBe(7)
  })

  it('书签可增删且始终升序去重', () => {
    db.toggleBookmark('a', 5)
    db.toggleBookmark('a', 1)
    db.toggleBookmark('a', 9)
    expect(db.getComic('a')!.bookmarks).toEqual([1, 5, 9])
    db.toggleBookmark('a', 5)
    expect(db.getComic('a')!.bookmarks).toEqual([1, 9])
  })

  it('reader 偏好是合并写入而不是整体覆盖', () => {
    db.updateComic('a', { reader: { mode: 'double' } })
    db.updateComic('a', { reader: { zoomScale: 1.5 } })
    expect(db.getComic('a')!.reader).toEqual({ mode: 'double', zoomScale: 1.5 })
  })
})

describe('分类', () => {
  beforeEach(() => {
    db.init()
    db.upsertComic(makeComic('a'))
    db.upsertComic(makeComic('b'))
  })

  it('批量加入 / 移出，方向由调用方决定', () => {
    const cat = db.createCategory('连载中')
    expect(db.setComicsCategory(['a', 'b'], cat.id, true)).toHaveLength(2)
    // 已经在里面的不会重复加，也不算变更
    expect(db.setComicsCategory(['a'], cat.id, true)).toHaveLength(0)
    expect(db.setComicsCategory(['a', 'b'], cat.id, false)).toHaveLength(2)
    expect(db.getComic('a')!.categoryIds).toEqual([])
  })

  it('分类不存在时批量操作不做任何事', () => {
    expect(db.setComicsCategory(['a'], '幽灵', true)).toEqual([])
  })

  it('删除分类只解除关联', () => {
    const cat = db.createCategory('已完结')
    db.setComicsCategory(['a'], cat.id, true)
    expect(db.deleteCategory(cat.id)).toBe(true)
    expect(db.getComic('a')).toBeTruthy()
    expect(db.getComic('a')!.categoryIds).toEqual([])
    expect(db.deleteCategory(cat.id)).toBe(false)
  })
})

describe('落盘', () => {
  it('写出的是紧凑 JSON（上千本时省一半体积）', () => {
    db.init()
    db.upsertComic(makeComic('a'))
    db.flushSync()
    const text = readLibraryText()
    expect(text.startsWith('{"version"')).toBe(true)
    expect(text).not.toContain('\n')
  })

  it('阅读进度走长防抖，不会每翻一页就重写整库', () => {
    db.init()
    db.upsertComic(makeComic('a'))
    db.flushSync()
    const before = readLibraryText()

    // 模拟连续翻页：只用 lazy 档
    for (let page = 1; page <= 30; page++) {
      db.updateComic('a', { lastReadPage: page }, { lazy: true })
    }
    // 5 秒的防抖还没到，磁盘上仍是旧内容
    expect(readLibraryText()).toBe(before)
    expect(db.getComic('a')!.lastReadPage).toBe(30)

    // 退出前的 flush 保证进度不丢
    db.flushSync()
    expect(readLibrary().comics[0].lastReadPage).toBe(30)
  })

  it('结构性改动不会被进度的长防抖拖延', () => {
    vi.useFakeTimers()
    try {
      db.init()
      db.upsertComic(makeComic('a'))
      db.flushSync()

      db.updateComic('a', { lastReadPage: 3 }, { lazy: true }) // 5s 后
      db.renameComic('a', '改过的名字') // 400ms 后，应当提前触发
      vi.advanceTimersByTime(500)
      const onDisk = readLibrary()
      expect(onDisk.comics[0].title).toBe('改过的名字')
      expect(onDisk.comics[0].lastReadPage).toBe(3)
    } finally {
      vi.useRealTimers()
    }
  })

  it('snapshot 是深拷贝，replaceAll 立即落盘', () => {
    db.init()
    db.upsertComic(makeComic('a'))
    const snap = db.snapshot()
    snap.comics[0].title = '只改快照'
    expect(db.getComic('a')!.title).not.toBe('只改快照')

    db.replaceAll({
      version: CURRENT_SCHEMA_VERSION,
      settings: db.getSettings(),
      comics: [makeComic('z')],
      categories: []
    })
    expect(db.listComics().map((c) => c.id)).toEqual(['z'])
    expect(readLibrary().comics[0].id).toBe('z')
  })
})

describe('normalizeLibraryData', () => {
  it('把任意来源的数据迁移 + 清洗成可用结构（导入备份时复用）', () => {
    const { data, migrated, fromVersion } = normalizeLibraryData({
      version: 2,
      settings: { theme: 'dark', cardSize: '巨大' },
      comics: [makeComic('a', { bookmarks: [3, 3, -1, 1.4, 'x'] })]
    })
    expect(migrated).toBe(true)
    expect(fromVersion).toBe(2)
    expect(data.version).toBe(CURRENT_SCHEMA_VERSION)
    expect(data.settings.theme).toBe('dark')
    expect(data.settings.cardSize).toBe('medium')
    expect(data.comics[0].bookmarks).toEqual([1, 3])
  })
})

describe('sanitizeBookmarks', () => {
  it('只保留非负整数，去重后升序', () => {
    expect(sanitizeBookmarks([5, 1, 5, 0])).toEqual([0, 1, 5])
    expect(sanitizeBookmarks([2.6, -3, NaN, Infinity, 'x', null])).toEqual([3])
    expect(sanitizeBookmarks('不是数组')).toEqual([])
  })
})
