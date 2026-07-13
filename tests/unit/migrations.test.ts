import { describe, expect, it } from 'vitest'
import {
  CURRENT_SCHEMA_VERSION,
  migrateLibraryData
} from '../../src/main/store/migrations'

describe('migrateLibraryData', () => {
  it('v1 → v2：settings 补上 cardSize，其余字段原样保留', () => {
    const v1 = {
      version: 1,
      settings: { theme: 'dark', readingDirection: 'rtl' },
      comics: [{ id: 'a', title: 'A', sourcePath: 'C:/a' }]
    }
    const { data, fromVersion, migrated } = migrateLibraryData(v1)
    expect(migrated).toBe(true)
    expect(fromVersion).toBe(1)
    expect(data.version).toBe(CURRENT_SCHEMA_VERSION)
    const settings = data.settings as Record<string, unknown>
    expect(settings.cardSize).toBe('medium')
    expect(settings.theme).toBe('dark')
    expect(settings.readingDirection).toBe('rtl')
    expect(data.comics).toEqual(v1.comics)
  })

  it('已是当前版本：不迁移不改动', () => {
    const now = {
      version: CURRENT_SCHEMA_VERSION,
      settings: { cardSize: 'large' },
      comics: []
    }
    const { data, migrated } = migrateLibraryData(now)
    expect(migrated).toBe(false)
    expect((data.settings as Record<string, unknown>).cardSize).toBe('large')
  })

  it('老数据里已有同名字段时以老数据为准', () => {
    const v1 = { version: 1, settings: { cardSize: 'small' }, comics: [] }
    const { data } = migrateLibraryData(v1)
    expect((data.settings as Record<string, unknown>).cardSize).toBe('small')
  })

  it('缺失 version 字段按 v1 处理', () => {
    const { data, migrated, fromVersion } = migrateLibraryData({ settings: {}, comics: [] })
    expect(fromVersion).toBe(1)
    expect(migrated).toBe(true)
    expect(data.version).toBe(CURRENT_SCHEMA_VERSION)
  })

  it('来自未来版本的数据：不降级改写，原样返回', () => {
    const future = { version: CURRENT_SCHEMA_VERSION + 5, settings: {}, comics: [], extra: 1 }
    const { data, migrated, fromVersion } = migrateLibraryData(future)
    expect(migrated).toBe(false)
    expect(fromVersion).toBe(CURRENT_SCHEMA_VERSION + 5)
    expect(data.version).toBe(CURRENT_SCHEMA_VERSION + 5)
    expect(data.extra).toBe(1)
  })

  it('完全无法识别的输入返回全新当前版本结构', () => {
    for (const junk of [null, undefined, 42, 'x', [1, 2]]) {
      const { data, migrated } = migrateLibraryData(junk)
      expect(migrated).toBe(false)
      expect(data.version).toBe(CURRENT_SCHEMA_VERSION)
    }
  })
})
