interface HandleCacheOptions<T> {
  /** 同时保留的句柄上限，超出时按最旧淘汰 */
  max: number
  /** 空闲多久自动释放（毫秒） */
  idleMs: number
  /** 打开句柄 */
  open: (key: string) => Promise<T>
  /** 释放句柄，不允许抛错 */
  close: (value: T) => void
}

/**
 * 压缩包句柄的 LRU 缓存。
 *
 * 阅读时会按页反复读同一个文件，每页重新打开一次代价很高（ZIP 要重解中央目录，
 * RAR / PDF 要重新把整个文件读进内存）。这里按「文件路径 → 已打开的句柄」缓存，
 * 空闲超时或超过上限时释放。同一个文件的并发打开会合并成一次。
 */
export class HandleCache<T> {
  private entries = new Map<string, { value: T; timer: NodeJS.Timeout }>()
  private pending = new Map<string, Promise<T>>()

  constructor(private readonly options: HandleCacheOptions<T>) {}

  private schedule(key: string): NodeJS.Timeout {
    const timer = setTimeout(() => this.release(key), this.options.idleMs)
    // 定时器不该拖住主进程退出
    timer.unref?.()
    return timer
  }

  async acquire(key: string): Promise<T> {
    const hit = this.entries.get(key)
    if (hit) {
      clearTimeout(hit.timer)
      hit.timer = this.schedule(key)
      // 重新插入以维持 LRU 顺序（Map 保持插入顺序）
      this.entries.delete(key)
      this.entries.set(key, hit)
      return hit.value
    }

    const inflight = this.pending.get(key)
    if (inflight) return inflight

    const task = this.options
      .open(key)
      .then((value) => {
        this.pending.delete(key)
        // 打开期间可能已被 release：新句柄天然是最新的，直接入缓存即可
        while (this.entries.size >= this.options.max) {
          const oldest = this.entries.keys().next().value
          if (oldest === undefined) break
          this.release(oldest)
        }
        this.entries.set(key, { value, timer: this.schedule(key) })
        return value
      })
      .catch((err) => {
        this.pending.delete(key)
        throw err
      })

    this.pending.set(key, task)
    return task
  }

  /** 主动释放某个句柄（文件被替换、读取失败重试时用） */
  release(key: string): void {
    const hit = this.entries.get(key)
    if (!hit) return
    clearTimeout(hit.timer)
    this.entries.delete(key)
    try {
      this.options.close(hit.value)
    } catch {
      /* 关闭失败无需处理，句柄已从缓存移除 */
    }
  }

  releaseAll(): void {
    for (const key of [...this.entries.keys()]) this.release(key)
  }
}
