/**
 * 日志脱敏。
 *
 * 排障日志会被贴到 issue 里，而漫画标题和来源路径本身就是隐私。
 * 这里的原则是「保留形状，去掉内容」：
 *   - 漫画只写 id 前 8 位，不写标题
 *   - 路径只保留盘符 / UNC 根、目录层数与扩展名
 * 用户操作时界面上的 toast 仍显示完整标题与路径，实时排障不受影响。
 */

const SEP = '\\'

/** 日志里代指一本漫画 */
export function comicRef(id: string): string {
  return `#${id.slice(0, 8)}`
}

/**
 * 路径脱敏。
 *   D:\comics\作者A\第01卷.cbz  →  D:\…2层\*.cbz
 *   \\NAS\share\a\b            →  \\…3层\*
 *   C:\Users\某人\AppData\x\y  →  C:\…4层\*
 */
export function redactPath(p: string): string {
  if (!p) return '(空路径)'
  // UNC 要在归一化之前判断：下面的正则会把连续分隔符压成一个，\\ 和 \ 就分不出来了
  const isUnc = /^[\\/]{2}/.test(p)
  const slashed = p.replace(/[\\/]+/g, '/')

  let prefix = ''
  let rest = slashed
  if (isUnc) {
    prefix = `${SEP}${SEP}` // \\
    rest = slashed.replace(/^\/+/, '')
  } else if (/^[a-zA-Z]:\//.test(slashed)) {
    prefix = `${slashed.slice(0, 2)}${SEP}` // D:\
    rest = slashed.slice(3)
  } else if (/^[a-zA-Z]:$/.test(slashed)) {
    return `${slashed}${SEP}*`
  } else if (slashed.startsWith('/')) {
    prefix = '/'
    rest = slashed.slice(1)
  }

  const segments = rest.split('/').filter(Boolean)
  const leaf = segments.pop() ?? ''
  const dot = leaf.lastIndexOf('.')
  const ext = dot > 0 ? leaf.slice(dot).toLowerCase() : ''
  const middle = segments.length > 0 ? `…${segments.length}层${SEP}` : ''
  return `${prefix}${middle}*${ext}`
}
