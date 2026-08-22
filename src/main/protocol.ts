import { promises as fsp } from 'node:fs'
import path from 'node:path'
import { protocol } from 'electron'
import { SourceError, readPage } from './archive'
import { logger } from './lib/logger'
import { db } from './store/db'
import { makePageThumbnail } from './thumbnail'
import { allowedComicOrigin } from './utils/cors'
import { mimeFor } from './utils/images'
import { comicRef } from './utils/redact'

export const COMIC_SCHEME = 'comic'

/**
 * 必须在 app ready 之前调用。
 * standard + stream 让 comic:// 表现得像 http://，可被 <img> 直接使用；
 * corsEnabled + 响应里的 ACAO 头让渲染进程能用 fetch 拿到字节
 * （自动裁边与封面重压需要把图片画进 canvas，跨源的 <img> 会污染画布）。
 */
export function registerComicSchemePrivileges(): void {
  protocol.registerSchemesAsPrivileged([
    {
      scheme: COMIC_SCHEME,
      privileges: {
        standard: true,
        secure: true,
        supportFetchAPI: true,
        corsEnabled: true,
        stream: true
      }
    }
  ])
}

/** 同一个来源只警告一次，避免被拒的请求刷满日志 */
const warnedOrigins = new Set<string>()

/**
 * 按来源决定要不要发 ACAO。
 * 只认本应用自己的页面（打包后的 file:// 与开发地址），其余一律不放行 ——
 * 现在窗口里跑不了第三方内容，这一层是防止将来有人引入 iframe / 远程页面时
 * 顺手就能读走本地漫画字节。
 */
function corsHeaders(request: Request): Record<string, string> {
  const origin = request.headers.get('origin')
  const allowed = allowedComicOrigin(origin, process.env['ELECTRON_RENDERER_URL'])
  if (!allowed) {
    if (origin && !warnedOrigins.has(origin)) {
      warnedOrigins.add(origin)
      logger.warn('security', `已拒绝来自 ${origin} 的 comic:// 跨源读取`)
    }
    return { Vary: 'Origin' }
  }
  return { 'Access-Control-Allow-Origin': allowed, Vary: 'Origin' }
}

function errorResponse(status: number, message: string, cors: Record<string, string>): Response {
  return new Response(message, {
    status,
    headers: { ...cors, 'Content-Type': 'text/plain; charset=utf-8' }
  })
}

/**
 * Buffer 的类型基于 ArrayBufferLike，DOM 的 BodyInit 不直接接受；
 * 运行时 Electron 接受 Uint8Array 视图，这里零拷贝转换后断言。
 */
function bufferBody(data: Buffer): BodyInit {
  return new Uint8Array(data.buffer, data.byteOffset, data.byteLength) as unknown as BodyInit
}

// ---------------------------------------------------------------------------
// 跳页缩略图缓存
//
// 缩略图条会来回滚动，每次都重新读盘 + 缩图太浪费。按字节总量做 LRU，
// nativeImage 解不了的格式（WebP/AVIF）会退回原图，只有小图才值得占缓存。
// ---------------------------------------------------------------------------

const THUMB_CACHE_MAX_BYTES = 24 * 1024 * 1024
const THUMB_CACHEABLE_MAX_BYTES = 512 * 1024

const thumbCache = new Map<string, { data: Buffer; mime: string }>()
let thumbCacheBytes = 0

function takeThumb(key: string): { data: Buffer; mime: string } | undefined {
  const hit = thumbCache.get(key)
  if (!hit) return undefined
  thumbCache.delete(key)
  thumbCache.set(key, hit)
  return hit
}

function putThumb(key: string, value: { data: Buffer; mime: string }): void {
  if (value.data.length > THUMB_CACHEABLE_MAX_BYTES) return
  thumbCache.set(key, value)
  thumbCacheBytes += value.data.length
  while (thumbCacheBytes > THUMB_CACHE_MAX_BYTES) {
    const oldest = thumbCache.keys().next().value
    if (oldest === undefined) break
    const evicted = thumbCache.get(oldest)
    thumbCache.delete(oldest)
    thumbCacheBytes -= evicted?.data.length ?? 0
  }
}

/** 重新扫描 / 移除 / 重定位后作废该漫画的缩略图 */
export function clearThumbCache(comicId?: string): void {
  if (!comicId) {
    thumbCache.clear()
    thumbCacheBytes = 0
    return
  }
  const prefix = `${comicId}:`
  for (const [key, value] of thumbCache) {
    if (!key.startsWith(prefix)) continue
    thumbCache.delete(key)
    thumbCacheBytes -= value.data.length
  }
}

/**
 * comic:// 协议：主进程按需把图片字节流给渲染进程的 <img>。
 * 相比 IPC 传 base64：不复制大字符串、天然支持并发与懒加载，是流畅翻页的关键。
 *
 *   comic://page/<comicId>/<pageIndex>    漫画内页（原图）
 *   comic://thumb/<comicId>/<pageIndex>   跳页缩略图（缩过的小图）
 *   comic://cover/<comicId>               封面
 */
export function registerComicProtocolHandler(): void {
  protocol.handle(COMIC_SCHEME, async (request) => {
    const cors = corsHeaders(request)
    try {
      const url = new URL(request.url)
      const segments = url.pathname.split('/').filter(Boolean)

      if (url.host === 'page' || url.host === 'thumb') {
        const [comicId, indexStr] = segments
        const comic = comicId ? db.getComic(comicId) : undefined
        if (!comic) return errorResponse(404, 'unknown comic', cors)
        const index = Number.parseInt(indexStr ?? '', 10)
        if (!Number.isInteger(index) || index < 0) {
          return errorResponse(400, 'bad page index', cors)
        }

        if (url.host === 'thumb') {
          const key = `${comicId}:${index}`
          const cached = takeThumb(key)
          if (cached) {
            return new Response(bufferBody(cached.data), {
              headers: {
                ...cors,
                'Content-Type': cached.mime,
                'Cache-Control': 'max-age=3600'
              }
            })
          }
          const page = await readPage(comic, index)
          const small = makePageThumbnail(page.data)
          // nativeImage 解不了的格式退回原图，由 CSS 负责显示尺寸
          const value = small ? { data: small, mime: 'image/jpeg' } : page
          putThumb(key, value)
          return new Response(bufferBody(value.data), {
            headers: {
              ...cors,
              'Content-Type': value.mime,
              'Cache-Control': 'max-age=3600'
            }
          })
        }

        const { data, mime } = await readPage(comic, index)
        return new Response(bufferBody(data), {
          headers: {
            ...cors,
            'Content-Type': mime,
            // 会话内短缓存：翻回上一页不用重新读盘，来源变化靠打开时的重扫描兜底
            'Cache-Control': 'max-age=300'
          }
        })
      }

      if (url.host === 'cover') {
        const [comicId] = segments
        const comic = comicId ? db.getComic(comicId) : undefined
        if (!comic || !comic.coverFile) return errorResponse(404, 'no cover', cors)
        // 防御：coverFile 来自数据文件，万一被篡改也不允许读到 covers 目录之外
        const coversDir = db.coversDir()
        const file = path.resolve(coversDir, comic.coverFile)
        const rel = path.relative(coversDir, file)
        if (rel.startsWith('..') || path.isAbsolute(rel)) {
          logger.warn('protocol', `拦截越界封面路径：${comicRef(comic.id)}`)
          return errorResponse(403, 'forbidden', cors)
        }
        const data = await fsp.readFile(file)
        return new Response(bufferBody(data), {
          headers: {
            ...cors,
            'Content-Type': mimeFor(comic.coverFile),
            'Cache-Control': 'max-age=3600'
          }
        })
      }

      return errorResponse(404, 'not found', cors)
    } catch (err) {
      if (err instanceof SourceError) return errorResponse(404, err.message, cors)
      logger.error('protocol', `comic:// 处理失败 ${request.url}`, err)
      return errorResponse(500, 'internal error', cors)
    }
  })
}
