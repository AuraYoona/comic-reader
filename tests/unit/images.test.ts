import { describe, expect, it } from 'vitest'
import { isImagePath, isJunkEntry, mimeFor } from '../../src/main/utils/images'

describe('isImagePath', () => {
  it('识别支持的扩展名（大小写不敏感）', () => {
    expect(isImagePath('a.jpg')).toBe(true)
    expect(isImagePath('a.JPEG')).toBe(true)
    expect(isImagePath('a.png')).toBe(true)
    expect(isImagePath('a.webp')).toBe(true)
    expect(isImagePath('a.gif')).toBe(true)
  })

  it('拒绝不支持的类型', () => {
    expect(isImagePath('a.txt')).toBe(false)
    expect(isImagePath('a.pdf')).toBe(false)
    expect(isImagePath('a.jpg.exe')).toBe(false)
    expect(isImagePath('noext')).toBe(false)
  })

  it('跳过隐藏文件，但保留下划线开头的正常命名', () => {
    expect(isImagePath('.DS_Store')).toBe(false)
    expect(isImagePath('._page1.jpg')).toBe(false)
    expect(isImagePath('_001.jpg')).toBe(true)
  })
})

describe('isJunkEntry', () => {
  it('过滤 __MACOSX 与隐藏目录', () => {
    expect(isJunkEntry('__MACOSX/vol1/1.jpg')).toBe(true)
    expect(isJunkEntry('.hidden/1.jpg')).toBe(true)
    expect(isJunkEntry('vol1/1.jpg')).toBe(false)
  })
})

describe('mimeFor', () => {
  it('返回正确的 MIME', () => {
    expect(mimeFor('x.jpg')).toBe('image/jpeg')
    expect(mimeFor('x.PNG')).toBe('image/png')
    expect(mimeFor('x.webp')).toBe('image/webp')
    expect(mimeFor('x.bin')).toBe('application/octet-stream')
  })
})
