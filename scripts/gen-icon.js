/**
 * 生成 build/icon.png（256×256 应用图标，无外部依赖）。
 * 图形：圆角深蓝底 + 白色翻开的书。
 * electron-builder 打包时会自动把它转换成 Windows .ico。
 *
 * 用法：node scripts/gen-icon.js
 */
const fs = require('node:fs')
const path = require('node:path')
const zlib = require('node:zlib')

const SIZE = 256

// ---------- 画布 ----------
const px = new Uint8Array(SIZE * SIZE * 4) // RGBA

function put(x, y, r, g, b, a = 255) {
  if (x < 0 || y < 0 || x >= SIZE || y >= SIZE) return
  const i = (y * SIZE + x) * 4
  px[i] = r
  px[i + 1] = g
  px[i + 2] = b
  px[i + 3] = a
}

// 圆角矩形内测试
function inRoundedRect(x, y, x0, y0, x1, y1, rad) {
  if (x < x0 || x > x1 || y < y0 || y > y1) return false
  const cx = Math.max(x0 + rad, Math.min(x, x1 - rad))
  const cy = Math.max(y0 + rad, Math.min(y, y1 - rad))
  const dx = x - cx
  const dy = y - cy
  return dx * dx + dy * dy <= rad * rad
}

// 凸四边形内测试（顶点顺时针）
function inQuad(x, y, quad) {
  let sign = 0
  for (let i = 0; i < 4; i++) {
    const [ax, ay] = quad[i]
    const [bx, by] = quad[(i + 1) % 4]
    const cross = (bx - ax) * (y - ay) - (by - ay) * (x - ax)
    if (cross !== 0) {
      const s = Math.sign(cross)
      if (sign === 0) sign = s
      else if (s !== sign) return false
    }
  }
  return true
}

// ---------- 图形 ----------
const BG = [59, 91, 219] // #3b5bdb 与应用强调色一致
const BG_DARK = [42, 66, 165] // 底部书脊阴影
const WHITE = [255, 255, 255]
const PAGE_SHADE = [219, 226, 252] // 内侧页阴影

// 翻开的书：左右两页（顺时针顶点）
const leftPage = [
  [52, 94],
  [122, 78],
  [122, 178],
  [52, 194]
]
const rightPage = [
  [134, 78],
  [204, 94],
  [204, 194],
  [134, 178]
]
// 内侧页（略小、偏灰，做出层次）
const leftInner = [
  [62, 102],
  [122, 89],
  [122, 178],
  [62, 191]
]
const rightInner = [
  [134, 89],
  [194, 102],
  [194, 191],
  [134, 178]
]

for (let y = 0; y < SIZE; y++) {
  for (let x = 0; x < SIZE; x++) {
    if (!inRoundedRect(x, y, 8, 8, 247, 247, 56)) continue
    let c = y > 196 && y < 214 && x > 88 && x < 168 ? BG : BG // 预留：底部装饰
    c = BG
    // 书脊底座（书页下方的深色梯形）
    if (
      inQuad(x, y, [
        [52, 194],
        [122, 178],
        [134, 178],
        [128, 200]
      ]) ||
      inQuad(x, y, [
        [128, 200],
        [134, 178],
        [204, 194],
        [204, 194]
      ])
    ) {
      c = BG_DARK
    }
    if (inQuad(x, y, leftPage) || inQuad(x, y, rightPage)) c = WHITE
    if (inQuad(x, y, leftInner) || inQuad(x, y, rightInner)) c = PAGE_SHADE
    // 中缝
    if (x >= 123 && x <= 133 && y >= 78 && y <= 194) c = BG_DARK
    put(x, y, c[0], c[1], c[2], 255)
  }
}

// ---------- PNG 编码 ----------
function crc32(buf) {
  let c
  const table =
    crc32.table ||
    (crc32.table = (() => {
      const t = new Int32Array(256)
      for (let n = 0; n < 256; n++) {
        c = n
        for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
        t[n] = c
      }
      return t
    })())
  c = 0 ^ -1
  for (let i = 0; i < buf.length; i++) c = (c >>> 8) ^ table[(c ^ buf[i]) & 0xff]
  return (c ^ -1) >>> 0
}

function chunk(type, data) {
  const len = Buffer.alloc(4)
  len.writeUInt32BE(data.length)
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data])
  const crc = Buffer.alloc(4)
  crc.writeUInt32BE(crc32(body))
  return Buffer.concat([len, body, crc])
}

const ihdr = Buffer.alloc(13)
ihdr.writeUInt32BE(SIZE, 0)
ihdr.writeUInt32BE(SIZE, 4)
ihdr[8] = 8 // bit depth
ihdr[9] = 6 // RGBA
// 每行前加 filter byte 0
const raw = Buffer.alloc(SIZE * (SIZE * 4 + 1))
for (let y = 0; y < SIZE; y++) {
  raw[y * (SIZE * 4 + 1)] = 0
  Buffer.from(px.buffer, y * SIZE * 4, SIZE * 4).copy(raw, y * (SIZE * 4 + 1) + 1)
}
const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk('IHDR', ihdr),
  chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
  chunk('IEND', Buffer.alloc(0))
])

const out = path.join(__dirname, '..', 'build', 'icon.png')
fs.mkdirSync(path.dirname(out), { recursive: true })
fs.writeFileSync(out, png)
console.log(`icon written: ${out} (${png.length} bytes)`)
