/**
 * comic:// 的跨源读取白名单（纯函数，可单独单元测试）。
 *
 * 自动裁边与封面重压必须用 fetch 取字节再画进 canvas —— 跨源的 <img> 会污染画布，
 * 之后的 getImageData / convertToBlob 全部会抛错。所以 comic:// 得回 ACAO 头。
 *
 * 但只放行本应用自己的页面：
 *   - 打包后渲染进程从 file:// 加载，fetch 带的 Origin 是字符串 "null"
 *   - 开发模式下是 electron-vite 起的本地地址
 * 其余来源一概不发 ACAO。<img> / <video> 这类普通加载根本不带 Origin，也就不需要这个头。
 */
export function allowedComicOrigin(origin: string | null, devUrl?: string): string | null {
  // 没有 Origin 说明不是 CORS 请求（普通的 <img> 加载），不需要放行头
  if (!origin) return null
  // file:// 页面的 Origin 就是字面量 "null"
  if (origin === 'null') return 'null'
  if (!devUrl) return null
  try {
    return origin === new URL(devUrl).origin ? origin : null
  } catch {
    return null
  }
}
