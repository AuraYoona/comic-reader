import { promises as fsp, readFileSync } from 'node:fs'
import path from 'node:path'
import { app } from 'electron'
import { createExtractorFromData, type Extractor } from 'node-unrar-js'
import { logger } from '../lib/logger'
import { SourceError, ioError } from './errors'
import { HandleCache } from './handleCache'
import type { ArchiveEntry, ArchiveReader } from './reader'

/**
 * RAR / CBR 支持。
 *
 * node-unrar-js 是纯 WASM 实现（不需要原生编译，打包无痛），但只能对
 * 「整个压缩包的字节」做随机访问，所以一个包必须整体读进内存。
 * 因此这里同时只保留 1 个句柄、空闲 45 秒即释放，并对体积设上限。
 */

const RAR_IDLE_MS = 45_000
const RAR_MAX_OPEN = 1
const RAR_MAX_BYTES = 1.5 * 1024 * 1024 * 1024

interface RarHandle {
  extractor: Extractor<Uint8Array>
  entries: ArchiveEntry[]
}

/** undefined = 用库自带的定位逻辑；只尝试一次 */
let cachedWasm: ArrayBuffer | undefined
let wasmLoaded = false

/**
 * 显式把 unrar.wasm 读出来交给库。
 * 打包成 asar 后库自身按 __dirname 定位 wasm 的方式未必可靠，
 * 而 fs 读 asar 内文件是透明的，这条路径更稳。失败则回退到库的默认行为。
 */
function getWasmBinary(): ArrayBuffer | undefined {
  if (wasmLoaded) return cachedWasm
  wasmLoaded = true
  try {
    const file = path.join(
      app.getAppPath(),
      'node_modules',
      'node-unrar-js',
      'dist',
      'js',
      'unrar.wasm'
    )
    const buf = readFileSync(file)
    cachedWasm = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength)
  } catch (err) {
    logger.warn('archive', 'unrar.wasm 显式加载失败，回退到库自带的定位方式', err)
  }
  return cachedWasm
}

/** 把 unrar 的错误码翻译成用户能看懂的话 */
function rarError(err: unknown): SourceError {
  if (err instanceof SourceError) return err
  const reason = (err as { reason?: unknown } | null)?.reason
  switch (typeof reason === 'string' ? reason : '') {
    case 'ERAR_MISSING_PASSWORD':
    case 'ERAR_BAD_PASSWORD':
      return new SourceError('这个 RAR 有密码保护，暂不支持加密的压缩包')
    case 'ERAR_UNKNOWN_FORMAT':
    case 'ERAR_BAD_ARCHIVE':
      return new SourceError('无法识别的 RAR，文件可能已损坏，或是分卷压缩包的其中一卷')
    case 'ERAR_BAD_DATA':
      return new SourceError('RAR 数据校验失败，文件可能已损坏')
    case 'ERAR_NO_MEMORY':
      return new SourceError('内存不足，无法解压这个 RAR')
    default:
      return new SourceError('读取 RAR 失败，文件可能已损坏或不是有效的 RAR/CBR')
  }
}

/** 一次性把整个文件读进一块 ArrayBuffer（先分配再填充，避免 Buffer→ArrayBuffer 的二次拷贝） */
async function readWholeFile(file: string): Promise<ArrayBuffer> {
  let size: number
  try {
    const st = await fsp.stat(file)
    if (!st.isFile()) throw new SourceError('该路径不是文件')
    size = st.size
  } catch (err) {
    throw err instanceof SourceError ? err : ioError(err, '无法访问 RAR 文件')
  }
  if (size > RAR_MAX_BYTES) {
    throw new SourceError('这个 RAR 超过 1.5 GB，解压需要整体载入内存，暂不支持')
  }

  const buffer = new ArrayBuffer(size)
  const view = Buffer.from(buffer)
  const handle = await fsp.open(file, 'r').catch((err) => {
    throw ioError(err, '无法打开 RAR 文件')
  })
  try {
    let done = 0
    while (done < size) {
      const { bytesRead } = await handle.read(view, done, size - done, done)
      if (bytesRead <= 0) break
      done += bytesRead
    }
    if (done < size) throw new SourceError('读取 RAR 时文件提前结束，可能已损坏')
  } catch (err) {
    throw err instanceof SourceError ? err : ioError(err, '读取 RAR 失败')
  } finally {
    await handle.close().catch(() => {})
  }
  return buffer
}

const cache = new HandleCache<RarHandle>({
  max: RAR_MAX_OPEN,
  idleMs: RAR_IDLE_MS,
  open: async (file) => {
    const data = await readWholeFile(file)
    try {
      const extractor = await createExtractorFromData({ data, wasmBinary: getWasmBinary() })
      const entries = [...extractor.getFileList().fileHeaders].map<ArchiveEntry>((h) => ({
        name: h.name,
        isDirectory: h.flags.directory
      }))
      return { extractor, entries }
    } catch (err) {
      throw rarError(err)
    }
  },
  // 没有文件描述符要关，丢掉引用即可让整包字节被回收
  close: () => {}
})

export const rarReader: ArchiveReader = {
  async list(file) {
    const handle = await cache.acquire(file)
    return handle.entries
  },

  async read(file, entry) {
    const { extractor } = await cache.acquire(file)
    try {
      const files = [...extractor.extract({ files: [entry] }).files]
      const data = files[0]?.extraction
      if (!data) throw new SourceError(`RAR 中找不到这一页：${entry}`, entry)
      // extraction 指向 WASM 堆，下次解压会被覆盖，必须拷贝出来
      return Buffer.from(data)
    } catch (err) {
      throw rarError(err)
    }
  },

  release: (file) => cache.release(file),
  releaseAll: () => cache.releaseAll()
}
