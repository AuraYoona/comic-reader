import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { buildZip } from '../helpers/zip'

/**
 * 归档层的端到端测试：文件夹 / ZIP / RAR 三条路径共用同一套对外接口，
 * 这里用真实的临时文件跑通「扫描 → 自然排序 → 按条目取字节」的全流程。
 */

// rar.ts 会从 app.getAppPath() 下定位 unrar.wasm，指到仓库根目录即可
vi.mock('electron', () => ({ app: { getAppPath: () => process.cwd() } }))
vi.mock('../../src/main/lib/logger', () => ({
  logger: { info: () => {}, warn: () => {}, error: () => {} }
}))

const { SourceError, closeAllSources, readEntry, releaseSource, scanSource } =
  await import('../../src/main/archive')

let dir = ''
const png = (n: number): Buffer => Buffer.from(`fake-png-${n}`, 'utf-8')

beforeEach(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'comic-archive-test-'))
})

afterEach(() => {
  closeAllSources()
  fs.rmSync(dir, { recursive: true, force: true })
})

describe('文件夹来源', () => {
  it('递归收集图片、自然排序、跳过垃圾与非图片', async () => {
    const root = path.join(dir, 'comic')
    fs.mkdirSync(path.join(root, 'vol2'), { recursive: true })
    fs.mkdirSync(path.join(root, '__MACOSX'), { recursive: true })
    fs.writeFileSync(path.join(root, '10.jpg'), png(10))
    fs.writeFileSync(path.join(root, '2.jpg'), png(2))
    fs.writeFileSync(path.join(root, '1.jpg'), png(1))
    fs.writeFileSync(path.join(root, 'note.txt'), 'x')
    fs.writeFileSync(path.join(root, '.DS_Store'), 'x')
    fs.writeFileSync(path.join(root, '__MACOSX', '3.jpg'), png(3))
    fs.writeFileSync(path.join(root, 'vol2', '1.avif'), png(21))

    // 1, 2, 10 而不是 1, 10, 2；子目录排在后面
    await expect(scanSource('folder', root)).resolves.toEqual([
      '1.jpg',
      '2.jpg',
      '10.jpg',
      'vol2/1.avif'
    ])
  })

  it('按相对路径取到原始字节', async () => {
    const root = path.join(dir, 'comic')
    fs.mkdirSync(root, { recursive: true })
    fs.writeFileSync(path.join(root, '1.png'), png(1))
    const { data, mime } = await readEntry('folder', root, '1.png')
    expect(data.toString()).toBe('fake-png-1')
    expect(mime).toBe('image/png')
  })

  it('路径不存在时给出能看懂的提示', async () => {
    await expect(scanSource('folder', path.join(dir, '没有这个'))).rejects.toThrow(SourceError)
    await expect(scanSource('folder', path.join(dir, '没有这个'))).rejects.toThrow(/已被移动或删除/)
  })
})

describe('ZIP / CBZ 来源', () => {
  const writeZip = (name: string): string => {
    const file = path.join(dir, name)
    fs.writeFileSync(
      file,
      buildZip([
        { name: 'ch1/10.jpg', data: png(10) },
        { name: 'ch1/2.jpg', data: png(2) },
        { name: 'ch1/1.jpg', data: png(1) },
        { name: '__MACOSX/ch1/._1.jpg', data: Buffer.from('junk') },
        { name: 'readme.txt', data: Buffer.from('x') },
        { name: 'cover.webp', data: png(0) }
      ])
    )
    return file
  }

  it('列出图片条目并自然排序', async () => {
    expect(await scanSource('archive', writeZip('a.zip'))).toEqual([
      'ch1/1.jpg',
      'ch1/2.jpg',
      'ch1/10.jpg',
      'cover.webp'
    ])
  })

  it('.cbz 与 .zip 走同一条实现', async () => {
    expect(await scanSource('archive', writeZip('a.cbz'))).toHaveLength(4)
  })

  it('按条目名取字节，MIME 跟着扩展名走', async () => {
    const file = writeZip('a.zip')
    expect((await readEntry('archive', file, 'ch1/2.jpg')).data.toString()).toBe('fake-png-2')
    expect((await readEntry('archive', file, 'cover.webp')).mime).toBe('image/webp')
  })

  it('句柄缓存命中后仍能正确读取，释放后可重新打开', async () => {
    const file = writeZip('a.zip')
    await scanSource('archive', file)
    expect((await readEntry('archive', file, 'ch1/1.jpg')).data.toString()).toBe('fake-png-1')
    releaseSource(file)
    expect((await readEntry('archive', file, 'ch1/1.jpg')).data.toString()).toBe('fake-png-1')
  })

  it('损坏的压缩包报错而不是抛出底层异常', async () => {
    const file = path.join(dir, 'broken.zip')
    fs.writeFileSync(file, Buffer.from('这不是一个 ZIP'))
    await expect(scanSource('archive', file)).rejects.toThrow(SourceError)
    await expect(scanSource('archive', file)).rejects.toThrow(/已损坏|有效的 ZIP/)
  })

  it('压缩包里没有图片时返回空列表，由上层决定怎么提示', async () => {
    const file = path.join(dir, 'empty.zip')
    fs.writeFileSync(file, buildZip([{ name: 'readme.txt', data: Buffer.from('x') }]))
    expect(await scanSource('archive', file)).toEqual([])
  })
})

describe('RAR / CBR 来源', () => {
  it('unrar.wasm 落在我们显式加载的位置上', () => {
    // rar.ts 按 app.getAppPath()/node_modules/... 定位 wasm；
    // 依赖升级后目录结构一旦变化，这里会先于用户发现
    const wasm = path.join(
      process.cwd(),
      'node_modules',
      'node-unrar-js',
      'dist',
      'js',
      'unrar.wasm'
    )
    expect(fs.existsSync(wasm)).toBe(true)
    expect(fs.statSync(wasm).size).toBeGreaterThan(10_000)
  })

  it('非法 RAR 被翻译成可读错误，而不是抛出底层异常', async () => {
    const file = path.join(dir, 'broken.cbr')
    fs.writeFileSync(file, Buffer.from('Rar! 但其实是假的'))
    await expect(scanSource('archive', file)).rejects.toThrow(SourceError)
    await expect(scanSource('archive', file)).rejects.toThrow(/RAR/)
  }, 30_000)
})

describe('格式分派', () => {
  it('不认识的压缩包扩展名直接拒绝', async () => {
    const file = path.join(dir, 'a.7z')
    fs.writeFileSync(file, Buffer.from('x'))
    await expect(scanSource('archive', file)).rejects.toThrow(/不支持的压缩包格式/)
  })

  it('把文件夹当压缩包（或反过来）会被识破', async () => {
    const folder = path.join(dir, 'plain')
    fs.mkdirSync(folder)
    await expect(scanSource('archive', folder)).rejects.toThrow(/不是文件/)

    const file = path.join(dir, 'a.zip')
    fs.writeFileSync(file, buildZip([]))
    await expect(scanSource('folder', file)).rejects.toThrow(/不是文件夹/)
  })
})
