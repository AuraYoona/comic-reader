import StreamZip from 'node-stream-zip'
import { SourceError } from './errors'
import { HandleCache } from './handleCache'
import type { ArchiveEntry, ArchiveReader } from './reader'

type ZipHandle = InstanceType<typeof StreamZip.async>

const ZIP_IDLE_MS = 60_000
const ZIP_MAX_OPEN = 4

const cache = new HandleCache<ZipHandle>({
  max: ZIP_MAX_OPEN,
  idleMs: ZIP_IDLE_MS,
  open: async (file) => {
    let zip: ZipHandle
    try {
      zip = new StreamZip.async({ file })
      await zip.entriesCount // 触发中央目录解析，尽早暴露损坏的包
    } catch {
      throw new SourceError('无法读取压缩包，文件可能已损坏或不是有效的 ZIP/CBZ')
    }
    return zip
  },
  close: (zip) => {
    void zip.close().catch(() => {})
  }
})

/** ZIP / CBZ：node-stream-zip 按条目随机读取，不需要整体解压 */
export const zipReader: ArchiveReader = {
  async list(file) {
    const zip = await cache.acquire(file)
    const entries = await zip.entries()
    return Object.values(entries).map<ArchiveEntry>((e) => ({
      name: e.name,
      isDirectory: e.isDirectory
    }))
  },

  async read(file, entry) {
    const zip = await cache.acquire(file)
    return zip.entryData(entry)
  },

  release: (file) => cache.release(file),
  releaseAll: () => cache.releaseAll()
}
