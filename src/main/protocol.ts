import { promises as fsp } from 'node:fs'
import path from 'node:path'
import { protocol } from 'electron'
import { SourceError, readPage } from './archive'
import { logger } from './lib/logger'
import { db } from './store/db'
import { mimeFor } from './utils/images'

export const COMIC_SCHEME = 'comic'

/**
 * 必须在 app ready 之前调用。
 * standard + stream 让 comic:// 表现得像 http://，可被 <img> 直接使用。
 */
export function registerComicSchemePrivileges(): void {
  protocol.registerSchemesAsPrivileged([
    {
      scheme: COMIC_SCHEME,
      privileges: {
        standard: true,
        secure: true,
        supportFetchAPI: true,
        stream: true
      }
    }
  ])
}

function errorResponse(status: number, message: string): Response {
  return new Response(message, {
    status,
    headers: { 'Content-Type': 'text/plain; charset=utf-8' }
  })
}

/**
 * Buffer 的类型基于 ArrayBufferLike，DOM 的 BodyInit 不直接接受；
 * 运行时 Electron 接受 Uint8Array 视图，这里零拷贝转换后断言。
 */
function bufferBody(data: Buffer): BodyInit {
  return new Uint8Array(data.buffer, data.byteOffset, data.byteLength) as unknown as BodyInit
}

/**
 * comic:// 协议：主进程按需把图片字节流给渲染进程的 <img>。
 * 相比 IPC 传 base64：不复制大字符串、天然支持并发与懒加载，是流畅翻页的关键。
 *
 *   comic://page/<comicId>/<pageIndex>   漫画内页
 *   comic://cover/<comicId>              封面
 */
export function registerComicProtocolHandler(): void {
  protocol.handle(COMIC_SCHEME, async (request) => {
    try {
      const url = new URL(request.url)
      const segments = url.pathname.split('/').filter(Boolean)

      if (url.host === 'page') {
        const [comicId, indexStr] = segments
        const comic = comicId ? db.getComic(comicId) : undefined
        if (!comic) return errorResponse(404, 'unknown comic')
        const index = Number.parseInt(indexStr ?? '', 10)
        if (!Number.isInteger(index) || index < 0) return errorResponse(400, 'bad page index')
        const { data, mime } = await readPage(comic, index)
        return new Response(bufferBody(data), {
          headers: {
            'Content-Type': mime,
            // 会话内短缓存：翻回上一页不用重新读盘，来源变化靠打开时的重扫描兜底
            'Cache-Control': 'max-age=300'
          }
        })
      }

      if (url.host === 'cover') {
        const [comicId] = segments
        const comic = comicId ? db.getComic(comicId) : undefined
        if (!comic || !comic.coverFile) return errorResponse(404, 'no cover')
        // 防御：coverFile 来自数据文件，万一被篡改也不允许读到 covers 目录之外
        const coversDir = db.coversDir()
        const file = path.resolve(coversDir, comic.coverFile)
        const rel = path.relative(coversDir, file)
        if (rel.startsWith('..') || path.isAbsolute(rel)) {
          logger.warn('protocol', `拦截越界封面路径：${comic.coverFile}`)
          return errorResponse(403, 'forbidden')
        }
        const data = await fsp.readFile(file)
        return new Response(bufferBody(data), {
          headers: {
            'Content-Type': mimeFor(comic.coverFile),
            'Cache-Control': 'max-age=3600'
          }
        })
      }

      return errorResponse(404, 'not found')
    } catch (err) {
      if (err instanceof SourceError) return errorResponse(404, err.message)
      logger.error('protocol', `comic:// 处理失败 ${request.url}`, err)
      return errorResponse(500, 'internal error')
    }
  })
}
