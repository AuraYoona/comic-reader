import { readFileSync } from 'node:fs'
import path from 'node:path'
import { app } from 'electron'
import { PDFiumLibrary, type PDFiumDocument } from '@hyzyla/pdfium'
import { logger } from '../lib/logger'
import { SourceError } from './errors'
import { HandleCache } from './handleCache'
import { encodePngRgba } from './png'
import { readWholeFile } from './readFile'
import type { ArchiveEntry, ArchiveReader } from './reader'

/**
 * PDF 支持。
 *
 * @hyzyla/pdfium 是纯 WASM 的 PDFium 包装（不需要原生编译，打包无痛），
 * 但文档必须整体读进内存。因此同时只保留 1 个句柄、空闲 45 秒即释放，
 * 并对体积设上限。页面按需渲成 PNG 再交给阅读器。
 */

const PDF_IDLE_MS = 45_000
const PDF_MAX_OPEN = 1
const PDF_MAX_BYTES = 1.5 * 1024 * 1024 * 1024
/** 72 DPI 的 2 倍：扫图漫画够清晰，单页 PNG 也不会大到撑爆内存 */
const PDF_RENDER_SCALE = 2

interface PdfHandle {
  document: PDFiumDocument
  entries: ArchiveEntry[]
}

let libraryPromise: Promise<PDFiumLibrary> | null = null

/**
 * 显式把 pdfium.wasm 读出来交给库。
 * 打包成 asar 后库自身按 import.meta.url / __dirname 定位 wasm 的方式未必可靠，
 * 而 fs 读 asar 内文件是透明的，这条路径更稳。
 */
function getWasmBinary(): ArrayBuffer {
  const file = path.join(
    app.getAppPath(),
    'node_modules',
    '@hyzyla',
    'pdfium',
    'dist',
    'pdfium.wasm'
  )
  const buf = readFileSync(file)
  return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength)
}

async function getLibrary(): Promise<PDFiumLibrary> {
  if (!libraryPromise) {
    libraryPromise = (async () => {
      try {
        return await PDFiumLibrary.init({ wasmBinary: getWasmBinary() })
      } catch (err) {
        libraryPromise = null
        logger.warn('archive', 'pdfium.wasm 加载失败', err)
        throw new SourceError('无法初始化 PDF 引擎，请尝试重新安装应用')
      }
    })()
  }
  return libraryPromise
}

function pageEntry(index: number): string {
  // 固定 4 位，自然排序与页码一致；阅读器只认图片扩展名
  return `${String(index + 1).padStart(4, '0')}.png`
}

function parsePageIndex(entry: string): number | null {
  const m = /^(\d+)\.png$/.exec(entry)
  if (!m) return null
  const n = Number.parseInt(m[1], 10)
  return Number.isInteger(n) && n >= 1 ? n - 1 : null
}

function pdfError(err: unknown): SourceError {
  if (err instanceof SourceError) return err
  const msg = err instanceof Error ? err.message : String(err)
  if (/password/i.test(msg)) return new SourceError('这个 PDF 有密码保护，暂不支持加密文件')
  if (/security/i.test(msg)) return new SourceError('这个 PDF 使用了不支持的加密方式')
  if (/format|corrupt/i.test(msg)) {
    return new SourceError('无法识别的 PDF，文件可能已损坏')
  }
  return new SourceError('读取 PDF 失败，文件可能已损坏或不是有效的 PDF')
}

const cache = new HandleCache<PdfHandle>({
  max: PDF_MAX_OPEN,
  idleMs: PDF_IDLE_MS,
  open: async (file) => {
    const data = await readWholeFile(
      file,
      PDF_MAX_BYTES,
      '这个 PDF 超过 1.5 GB，渲染需要整体载入内存，暂不支持'
    )
    const library = await getLibrary()
    try {
      const document = await library.loadDocument(new Uint8Array(data))
      const count = document.getPageCount()
      if (count <= 0) {
        document.destroy()
        throw new SourceError('这个 PDF 里没有页面')
      }
      const entries: ArchiveEntry[] = Array.from({ length: count }, (_, i) => ({
        name: pageEntry(i),
        isDirectory: false
      }))
      return { document, entries }
    } catch (err) {
      throw pdfError(err)
    }
  },
  close: (handle) => {
    try {
      handle.document.destroy()
    } catch {
      /* 关闭失败无需处理，句柄已从缓存移除 */
    }
  }
})

export const pdfReader: ArchiveReader = {
  async list(file) {
    const handle = await cache.acquire(file)
    return handle.entries
  },

  async read(file, entry) {
    const index = parsePageIndex(entry)
    if (index === null) throw new SourceError(`PDF 中找不到这一页：${entry}`, entry)
    const { document } = await cache.acquire(file)
    const count = document.getPageCount()
    if (index >= count) throw new SourceError(`PDF 中找不到这一页：${entry}`, entry)
    try {
      const page = document.getPage(index)
      const rendered = await page.render({
        scale: PDF_RENDER_SCALE,
        render: 'bitmap'
      })
      return encodePngRgba(rendered.width, rendered.height, rendered.data)
    } catch (err) {
      throw pdfError(err)
    }
  },

  release: (file) => cache.release(file),
  releaseAll: () => cache.releaseAll()
}
