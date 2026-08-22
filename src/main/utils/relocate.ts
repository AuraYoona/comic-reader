import path from 'node:path'

/** 重定位索引里的一个候选项（新根目录下的某个文件夹或压缩包） */
export interface IndexedEntry {
  /** 完整路径 */
  path: string
  /** 文件夹名 / 压缩包文件名（原样） */
  name: string
  /** 所在目录的名字，同名歧义时用来二次比对 */
  parent: string
}

/** 同名比较统一小写（Windows 大小写不敏感，跨盘搬运也常伴随改名大小写） */
function key(name: string): string {
  return name.toLowerCase()
}

/** 建立「名字 → 候选项」索引，同名的按发现顺序排列 */
export function buildNameIndex(entries: IndexedEntry[]): Map<string, IndexedEntry[]> {
  const index = new Map<string, IndexedEntry[]>()
  for (const entry of entries) {
    const k = key(entry.name)
    const bucket = index.get(k)
    if (bucket) bucket.push(entry)
    else index.set(k, [entry])
  }
  return index
}

/** 兼容 Windows 反斜杠与正斜杠的路径拆分 */
function segments(p: string): string[] {
  return p.split(/[\\/]+/).filter(Boolean)
}

/**
 * 在索引里为一条旧路径找新路径。
 *
 * 先按文件（夹）名精确匹配；同名有多个时，优先选父目录名也一致的那个
 * （例如同一部作品在 `作者A/单行本` 和 `作者B/单行本` 下都有 `第01卷`）。
 * 找不到返回 null，绝不猜。
 */
export function pickMatch(oldPath: string, index: Map<string, IndexedEntry[]>): string | null {
  const parts = segments(oldPath)
  const name = parts[parts.length - 1]
  if (!name) return null
  const bucket = index.get(key(name))
  if (!bucket || bucket.length === 0) return null
  if (bucket.length === 1) return bucket[0].path

  const oldParent = parts[parts.length - 2]
  if (oldParent) {
    const sameParent = bucket.find((e) => key(e.parent) === key(oldParent))
    if (sameParent) return sameParent.path
  }
  return bucket[0].path
}

/** 把一个绝对路径转成索引项 */
export function toIndexedEntry(fullPath: string): IndexedEntry {
  return {
    path: fullPath,
    name: path.basename(fullPath),
    parent: path.basename(path.dirname(fullPath))
  }
}
