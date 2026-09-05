import { describe, expect, it } from 'vitest'
import { encodePngRgba } from '../../src/main/archive/png'

const PNG_SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])

function readIhdr(png: Buffer): {
  width: number
  height: number
  bitDepth: number
  colorType: number
} {
  expect(png.subarray(0, 8).equals(PNG_SIG)).toBe(true)
  expect(png.readUInt32BE(8)).toBe(13)
  expect(png.subarray(12, 16).toString('ascii')).toBe('IHDR')
  return {
    width: png.readUInt32BE(16),
    height: png.readUInt32BE(20),
    bitDepth: png[24],
    colorType: png[25]
  }
}

describe('encodePngRgba', () => {
  it('写出合法的 8bit RGBA PNG', () => {
    const png = encodePngRgba(2, 1, Uint8Array.from([255, 0, 0, 255, 0, 255, 0, 128]))
    const ihdr = readIhdr(png)
    expect(ihdr).toEqual({ width: 2, height: 1, bitDepth: 8, colorType: 6 })
    expect(png.subarray(-8).toString('ascii')).toContain('IEND')
  })

  it('拒绝非法尺寸或过短的像素缓冲', () => {
    expect(() => encodePngRgba(0, 1, new Uint8Array(4))).toThrow(/invalid png size/)
    expect(() => encodePngRgba(1, 1, new Uint8Array(3))).toThrow(/too small/)
  })
})
