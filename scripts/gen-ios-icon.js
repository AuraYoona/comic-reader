// 生成 iOS App 图标（1024×1024 PNG，无外部依赖：手写 PNG 编码 + 简单光栅化）。
// 用法：node scripts/gen-ios-icon.js
// 输出：ios/App/ComicReader/Assets.xcassets/AppIcon.appiconset/icon-1024.png

const fs = require('node:fs')
const path = require('node:path')
const zlib = require('node:zlib')

const SIZE = 1024

// ---- 调色（与桌面版深色主题同源）----
const BG = [0x15, 0x15, 0x19] // #151519
const COVER = [0x6d, 0x8b, 0xff] // #6d8bff
const PAGE = [0xf2, 0xf3, 0xf7]
const SPINE = [0x3b, 0x5b, 0xdb] // #3b5bdb

// ---- 几何（居中书本：封面 + 书脊 + 两条“文字”线）----
const cover = { x: 232, y: 172, w: 560, h: 680, r: 64 }
const spine = { x: 232, y: 172, w: 84, h: 680, r: 64 }
const line1 = { x: 380, y: 400, w: 300, h: 44, r: 22 }
const line2 = { x: 380, y: 496, w: 220, h: 44, r: 22 }
const dot = { cx: 430, cy: 640, r: 34 } // 书签圆点

/** 圆角矩形 SDF：<0 内部 */
function roundedRectSDF(px, py, rect) {
  const halfW = rect.w / 2
  const halfH = rect.h / 2
  const cx = rect.x + halfW
  const cy = rect.y + halfH
  const dx = Math.abs(px - cx) - (halfW - rect.r)
  const dy = Math.abs(py - cy) - (halfH - rect.r)
  const outside = Math.hypot(Math.max(dx, 0), Math.max(dy, 0))
  return outside + Math.min(Math.max(dx, dy), 0) - rect.r
}

function circleSDF(px, py, c) {
  return Math.hypot(px - c.cx, py - c.cy) - c.r
}

/** 像素颜色（带 2×2 超采样抗锯齿），返回 [r,g,b] */
function sampleColor(px, py) {
  let r = 0
  let g = 0
  let b = 0
  const offsets = [
    [0.25, 0.25],
    [0.75, 0.25],
    [0.25, 0.75],
    [0.75, 0.75]
  ]
  for (const [ox, oy] of offsets) {
    const x = px + ox
    const y = py + oy
    let color = BG
    // 从底到顶叠加（后面的覆盖前面的）
    if (roundedRectSDF(x, y, cover) <= 0) color = COVER
    if (roundedRectSDF(x, y, spine) <= 0) color = SPINE
    if (roundedRectSDF(x, y, line1) <= 0 || roundedRectSDF(x, y, line2) <= 0) color = PAGE
    if (circleSDF(x, y, dot) <= 0) color = PAGE
    r += color[0]
    g += color[1]
    b += color[2]
  }
  return [Math.round(r / 4), Math.round(g / 4), Math.round(b / 4)]
}

// ---- PNG 编码 ----
const CRC_TABLE = (() => {
  const table = new Int32Array(256)
  for (let n = 0; n < 256; n++) {
    let c = n
    for (let k = 0; k < 8; k++) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
    }
    table[n] = c
  }
  return table
})()

function crc32(buf) {
  let c = 0xffffffff
  for (let i = 0; i < buf.length; i++) {
    c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8)
  }
  return (c ^ 0xffffffff) >>> 0
}

function chunk(type, data) {
  const len = Buffer.alloc(4)
  len.writeUInt32BE(data.length)
  const typeBuf = Buffer.from(type, 'ascii')
  const crc = Buffer.alloc(4)
  crc.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])))
  return Buffer.concat([len, typeBuf, data, crc])
}

function encodePNG(rgba, width, height) {
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(width, 0)
  ihdr.writeUInt32BE(height, 4)
  ihdr[8] = 8 // bit depth
  ihdr[9] = 6 // color type RGBA
  ihdr[10] = 0 // compression
  ihdr[11] = 0 // filter
  ihdr[12] = 0 // interlace
  // 每行前缀 filter=0
  const stride = width * 4
  const raw = Buffer.alloc((stride + 1) * height)
  for (let y = 0; y < height; y++) {
    raw[y * (stride + 1)] = 0
    rgba.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride)
  }
  const idat = zlib.deflateSync(raw, { level: 9 })
  return Buffer.concat([
    sig,
    chunk('IHDR', ihdr),
    chunk('IDAT', idat),
    chunk('IEND', Buffer.alloc(0))
  ])
}

// ---- 主流程 ----
const rgba = Buffer.alloc(SIZE * SIZE * 4)
for (let y = 0; y < SIZE; y++) {
  for (let x = 0; x < SIZE; x++) {
    const [r, g, b] = sampleColor(x, y)
    const i = (y * SIZE + x) * 4
    rgba[i] = r
    rgba[i + 1] = g
    rgba[i + 2] = b
    rgba[i + 3] = 255
  }
}

const png = encodePNG(rgba, SIZE, SIZE)
const out = path.join(
  __dirname,
  '..',
  'ios',
  'App',
  'ComicReader',
  'Assets.xcassets',
  'AppIcon.appiconset',
  'icon-1024.png'
)
fs.writeFileSync(out, png)
console.log(`icon written: ${out} (${png.length} bytes)`)

// 自检：解开 IHDR 摘要
console.log(`signature ok: ${png.subarray(1, 4).toString('ascii') === 'PNG'}`)
