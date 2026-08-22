import { redactPath } from '../utils/redact'

/**
 * 来源相关的可预期错误（路径丢失、压缩包损坏等），消息可直接展示给用户。
 *
 * message 里带完整路径是故意的 —— 界面上要让用户看清是哪个文件出了问题；
 * 写日志时改用 logMessage，路径会被换成脱敏形式。
 */
export class SourceError extends Error {
  constructor(
    message: string,
    /** 消息里嵌入的用户路径，写日志时需要替换掉 */
    readonly path?: string
  ) {
    super(message)
    this.name = 'SourceError'
  }

  /** 写日志用的文案：把用户路径换成「盘符 + 层数 + 扩展名」 */
  get logMessage(): string {
    if (!this.path) return this.message
    return this.message.split(this.path).join(redactPath(this.path))
  }
}

/** 把文件系统 errno 翻译成用户能看懂的话 */
export function ioError(err: unknown, fallback: string, path?: string): SourceError {
  const code = (err as NodeJS.ErrnoException | null)?.code
  switch (code) {
    case 'ENOENT':
      return new SourceError('文件或文件夹不存在，可能已被移动或删除')
    case 'EACCES':
    case 'EPERM':
      return new SourceError('没有读取权限，请检查文件（夹）的访问权限')
    case 'EBUSY':
      return new SourceError('文件正被其他程序占用，请稍后重试')
    case 'EMFILE':
    case 'ENFILE':
      return new SourceError('系统打开的文件过多，请稍后重试')
    default:
      return new SourceError(fallback, path)
  }
}
