import fs from 'node:fs'
import path from 'node:path'

const MAX_LOG_BYTES = 2 * 1024 * 1024

type Level = 'INFO' | 'WARN' | 'ERROR'

/**
 * 极简文件日志：写到 userData/logs/main.log，超过 2MB 轮转为 main.old.log。
 * init 之前调用只输出到控制台，任何写入失败都静默降级，绝不因日志拖垮应用。
 */
class Logger {
  private stream: fs.WriteStream | null = null

  init(userDataDir: string): void {
    try {
      const dir = path.join(userDataDir, 'logs')
      fs.mkdirSync(dir, { recursive: true })
      const file = path.join(dir, 'main.log')
      try {
        if (fs.existsSync(file) && fs.statSync(file).size > MAX_LOG_BYTES) {
          const old = path.join(dir, 'main.old.log')
          fs.rmSync(old, { force: true })
          fs.renameSync(file, old)
        }
      } catch {
        /* 轮转失败继续追加 */
      }
      this.stream = fs.createWriteStream(file, { flags: 'a' })
      this.info('logger', '---- 应用启动 ----')
    } catch {
      this.stream = null
    }
  }

  /**
   * 把错误渲染成一行日志。
   *
   * 带 logMessage 的错误（SourceError）用它的脱敏文案 —— 原始 message 里嵌了
   * 用户的漫画路径，那是给界面看的，不该落到可能被分享出去的日志里。
   * 其余错误照常打堆栈：里面只有本应用的源码位置。
   */
  private describe(err: unknown): string {
    if (err === undefined) return ''
    const redacted = (err as { logMessage?: unknown } | null)?.logMessage
    if (typeof redacted === 'string') return ` :: ${redacted}`
    if (err instanceof Error) return ` :: ${err.stack ?? err.message}`
    return ` :: ${String(err)}`
  }

  private write(level: Level, scope: string, msg: string, err?: unknown): void {
    const line = `[${new Date().toISOString()}] [${level}] [${scope}] ${msg}${this.describe(err)}`
    if (level === 'ERROR') console.error(line)
    else if (level === 'WARN') console.warn(line)
    else console.log(line)
    try {
      this.stream?.write(line + '\n')
    } catch {
      /* ignore */
    }
  }

  info(scope: string, msg: string): void {
    this.write('INFO', scope, msg)
  }

  warn(scope: string, msg: string, err?: unknown): void {
    this.write('WARN', scope, msg, err)
  }

  error(scope: string, msg: string, err?: unknown): void {
    this.write('ERROR', scope, msg, err)
  }

  close(): void {
    try {
      this.stream?.end()
    } catch {
      /* ignore */
    }
    this.stream = null
  }
}

export const logger = new Logger()
