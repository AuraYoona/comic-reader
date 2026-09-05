import { promises as fsp } from 'node:fs'
import { SourceError, ioError } from './errors'

/**
 * 把整个文件读进一块 ArrayBuffer（先分配再填充，避免 Buffer→ArrayBuffer 的二次拷贝）。
 * RAR / PDF 的 WASM 实现都只能对整包字节做随机访问，两条路径共用这里。
 */
export async function readWholeFile(
  file: string,
  maxBytes: number,
  tooLarge: string
): Promise<ArrayBuffer> {
  let size: number
  try {
    const st = await fsp.stat(file)
    if (!st.isFile()) throw new SourceError('该路径不是文件')
    size = st.size
  } catch (err) {
    throw err instanceof SourceError ? err : ioError(err, '无法访问文件')
  }
  if (size > maxBytes) throw new SourceError(tooLarge)

  const buffer = new ArrayBuffer(size)
  const view = Buffer.from(buffer)
  const handle = await fsp.open(file, 'r').catch((err) => {
    throw ioError(err, '无法打开文件')
  })
  try {
    let done = 0
    while (done < size) {
      const { bytesRead } = await handle.read(view, done, size - done, done)
      if (bytesRead <= 0) break
      done += bytesRead
    }
    if (done < size) throw new SourceError('读取文件时提前结束，可能已损坏')
  } catch (err) {
    throw err instanceof SourceError ? err : ioError(err, '读取文件失败')
  } finally {
    await handle.close().catch(() => {})
  }
  return buffer
}
