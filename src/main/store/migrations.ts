/**
 * library.json 的 schema 迁移管线。
 *
 * 纯函数、不依赖 electron，可单独做单元测试。
 * 新增字段/结构变化时：CURRENT_SCHEMA_VERSION +1，在 MIGRATIONS 里加一步
 * `旧版本号 → 迁移函数`，db 加载时自动逐级升级并备份原文件。
 *
 * 版本历史：
 *   v1  MVP：{ version, settings, comics }
 *   v2  settings 增加 cardSize（书架卡片大小）
 */

export const CURRENT_SCHEMA_VERSION = 2

type AnyRecord = Record<string, unknown>

export interface MigrationOutcome {
  data: AnyRecord
  fromVersion: number
  migrated: boolean
}

/** 每一步只负责 n → n+1，保持小而可测 */
const MIGRATIONS: Record<number, (data: AnyRecord) => AnyRecord> = {
  1: (data) => {
    const settings = (data.settings ?? {}) as AnyRecord
    return {
      ...data,
      version: 2,
      // 默认值放前面：老数据里已有同名字段时以老数据为准
      settings: { cardSize: 'medium', ...settings }
    }
  }
}

function readVersion(data: AnyRecord): number {
  const v = data.version
  return typeof v === 'number' && Number.isInteger(v) && v >= 1 ? v : 1
}

export function migrateLibraryData(raw: unknown): MigrationOutcome {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    // 完全无法识别：当作全新数据（调用方的 sanitize 会给出空库）
    return {
      data: { version: CURRENT_SCHEMA_VERSION },
      fromVersion: CURRENT_SCHEMA_VERSION,
      migrated: false
    }
  }

  let data: AnyRecord = { ...(raw as AnyRecord) }
  const fromVersion = readVersion(data)

  // 来自更新版本的数据（例如用户回退安装了旧版）：
  // 不做降级改写，按已知字段尽力读取，向前兼容交给 sanitize
  if (fromVersion > CURRENT_SCHEMA_VERSION) {
    return { data, fromVersion, migrated: false }
  }

  let version = fromVersion
  while (version < CURRENT_SCHEMA_VERSION) {
    const step = MIGRATIONS[version]
    if (!step) break // 缺失步骤：停在当前形态，靠 sanitize 兜底
    data = step(data)
    version++
  }
  data.version = version

  return { data, fromVersion, migrated: version !== fromVersion }
}
