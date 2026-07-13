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

  private write(level: Level, scope: string, msg: string, err?: unknown): void {
    const detail =
      err instanceof Error
        ? ` :: ${err.stack ?? err.message}`
        : err !== undefined
          ? ` :: ${String(err)}`
          : ''
    const line = `[${new Date().toISOString()}] [${level}] [${scope}] ${msg}${detail}`
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
