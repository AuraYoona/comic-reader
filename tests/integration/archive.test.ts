import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { buildPdf } from '../helpers/pdf'
import { buildZip } from '../helpers/zip'

/**
 * 归档层的端到端测试：文件夹 / ZIP / RAR / PDF 四条路径共用同一套对外接口，
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
  // 压缩包句柄的 close() 是异步的（退出时 fire-and-forget 就够用），
  // Windows 上删目录可能正好撞上还没关完的句柄 —— 用 Node 内建重试兜住；
  // 真删不掉也不必失败，临时目录交给系统回收
  try {
    fs.rmSync(dir, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 })
  } catch {
    /* 忽略残留的临时目录 */
  }
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

describe('PDF 来源', () => {
  it('pdfium.wasm 落在我们显式加载的位置上', () => {
    const wasm = path.join(
      process.cwd(),
      'node_modules',
      '@hyzyla',
      'pdfium',
      'dist',
      'pdfium.wasm'
    )
    expect(fs.existsSync(wasm)).toBe(true)
    expect(fs.statSync(wasm).size).toBeGreaterThan(10_000)
  })

  const writePdf = (name: string): string => {
    const file = path.join(dir, name)
    fs.writeFileSync(
      file,
      buildPdf([
        { width: 200, height: 300, r: 0.8, g: 0.1, b: 0.1 },
        { width: 200, height: 300, r: 0.1, g: 0.8, b: 0.1 }
      ])
    )
    return file
  }

  it('按页列出虚拟 PNG 条目', async () => {
    expect(await scanSource('archive', writePdf('a.pdf'))).toEqual(['0001.png', '0002.png'])
  }, 30_000)

  it('按条目渲成 PNG 字节，MIME 为 image/png', async () => {
    const file = writePdf('a.pdf')
    const { data, mime } = await readEntry('archive', file, '0001.png')
    expect(mime).toBe('image/png')
    expect(
      data.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))
    ).toBe(true)
    expect(data.readUInt32BE(16)).toBe(400) // 200pt × scale 2
    expect(data.readUInt32BE(20)).toBe(600)
  }, 30_000)

  it('句柄缓存命中后仍能正确读取，释放后可重新打开', async () => {
    const file = writePdf('a.pdf')
    await scanSource('archive', file)
    const first = await readEntry('archive', file, '0002.png')
    expect(first.mime).toBe('image/png')
    releaseSource(file)
    const again = await readEntry('archive', file, '0002.png')
    expect(again.data.equals(first.data)).toBe(true)
  }, 30_000)

  it('非法 PDF 被翻译成可读错误，而不是抛出底层异常', async () => {
    const file = path.join(dir, 'broken.pdf')
    fs.writeFileSync(file, Buffer.from('%PDF-1.4 但其实是假的'))
    await expect(scanSource('archive', file)).rejects.toThrow(SourceError)
    await expect(scanSource('archive', file)).rejects.toThrow(/PDF/)
  }, 30_000)
})

describe('格式分派', () => {
  it('不认识的文件扩展名直接拒绝', async () => {
    const file = path.join(dir, 'a.7z')
    fs.writeFileSync(file, Buffer.from('x'))
    await expect(scanSource('archive', file)).rejects.toThrow(/不支持的文件格式/)
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
