import { deflateSync } from 'node:zlib'

/**
 * 把 RGBA 位图压成 PNG。PDF 页渲染产出的是原始像素，阅读器只吃图片字节，
 * 这里用 Node 自带的 zlib，不额外拉原生模块。
 */

const SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])

const CRC_TABLE = (() => {
  const table = new Int32Array(256)
  for (let n = 0; n < 256; n++) {
    let c = n
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
    table[n] = c
  }
  return table
})()

function crc32(buf: Buffer): number {
  let c = -1
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8)
  return (c ^ -1) >>> 0
}

function chunk(type: string, data: Buffer): Buffer {
  const typeBuf = Buffer.from(type, 'ascii')
  const len = Buffer.alloc(4)
  len.writeUInt32BE(data.length, 0)
  const crcBuf = Buffer.alloc(4)
  crcBuf.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])), 0)
  return Buffer.concat([len, typeBuf, data, crcBuf])
}

/** 把紧密排列的 RGBA 像素编码为 PNG（8bit、非交错、filter 0） */
export function encodePngRgba(width: number, height: number, rgba: Uint8Array): Buffer {
  if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0) {
    throw new Error('invalid png size')
  }
  const stride = width * 4
  if (rgba.length < stride * height) {
    throw new Error('rgba buffer too small')
  }

  const raw = Buffer.alloc((stride + 1) * height)
  for (let y = 0; y < height; y++) {
    const dest = y * (stride + 1)
    raw[dest] = 0
    raw.set(rgba.subarray(y * stride, y * stride + stride), dest + 1)
  }

  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(width, 0)
  ihdr.writeUInt32BE(height, 4)
  ihdr[8] = 8 // bit depth
  ihdr[9] = 6 // color type: RGBA
  // compression / filter / interlace 保持 0

  return Buffer.concat([
    SIGNATURE,
    chunk('IHDR', ihdr),
    // level 4：大页渲染走热路径，压缩率让一点给速度
    chunk('IDAT', deflateSync(raw, { level: 4 })),
    chunk('IEND', Buffer.alloc(0))
  ])
}
