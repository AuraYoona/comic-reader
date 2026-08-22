import { describe, expect, it } from 'vitest'
import { ARCHIVE_EXTS, isArchivePath, stripArchiveExt } from '../../src/shared/archives'
import { coverNeedsThumbnail, isGeneratedCover } from '../../src/shared/covers'

describe('isArchivePath', () => {
  it('识别四种压缩包（大小写不敏感）', () => {
    expect(isArchivePath('a.zip')).toBe(true)
    expect(isArchivePath('a.CBZ')).toBe(true)
    expect(isArchivePath('a.rar')).toBe(true)
    expect(isArchivePath('a.CbR')).toBe(true)
  })

  it('拒绝其它类型与无扩展名', () => {
    expect(isArchivePath('a.7z')).toBe(false)
    expect(isArchivePath('a.pdf')).toBe(false)
    expect(isArchivePath('folder')).toBe(false)
    expect(isArchivePath('.zip')).toBe(false) // 隐藏文件，不算扩展名
  })

  it('只看最后一段路径', () => {
    expect(isArchivePath('D:/a.zip/b')).toBe(false)
    expect(isArchivePath('D:/dir.rar/vol1.cbz')).toBe(true)
  })

  it('四种扩展名都在清单里', () => {
    expect([...ARCHIVE_EXTS].sort()).toEqual(['.cbr', '.cbz', '.rar', '.zip'])
  })
})

describe('stripArchiveExt', () => {
  it('去掉压缩包扩展名', () => {
    expect(stripArchiveExt('孤独摇滚 v01.cbz')).toBe('孤独摇滚 v01')
    expect(stripArchiveExt('x.RAR')).toBe('x')
  })

  it('不是压缩包就原样返回', () => {
    expect(stripArchiveExt('普通文件夹')).toBe('普通文件夹')
    expect(stripArchiveExt('封面.jpg')).toBe('封面.jpg')
  })

  it('只去掉最后一个扩展名', () => {
    expect(stripArchiveExt('vol.1.cbz')).toBe('vol.1')
  })
})

describe('封面是否需要二次压缩', () => {
  it('.jpg 是主进程生成的缩略图', () => {
    expect(isGeneratedCover('abc-123.jpg')).toBe(true)
    expect(isGeneratedCover('abc-123.JPG')).toBe(true)
    expect(coverNeedsThumbnail('abc-123.jpg')).toBe(false)
  })

  it('其它扩展名说明是原图直存，要让渲染进程重压', () => {
    expect(isGeneratedCover('abc.webp')).toBe(false)
    expect(coverNeedsThumbnail('abc.webp')).toBe(true)
    expect(coverNeedsThumbnail('abc.avif')).toBe(true)
    expect(coverNeedsThumbnail('abc.gif')).toBe(true)
  })

  it('没有封面时不需要处理', () => {
    expect(isGeneratedCover(null)).toBe(false)
    expect(coverNeedsThumbnail(null)).toBe(false)
  })
})
