import { describe, expect, it } from 'vitest'
import { SourceError } from '../../src/main/archive/errors'
import { allowedComicOrigin } from '../../src/main/utils/cors'
import { comicRef, redactPath } from '../../src/main/utils/redact'

const DEV = 'http://localhost:5173'

describe('allowedComicOrigin', () => {
  it('普通 <img> 加载不带 Origin，不需要放行头', () => {
    expect(allowedComicOrigin(null, DEV)).toBeNull()
    expect(allowedComicOrigin('', DEV)).toBeNull()
  })

  it('打包后渲染进程走 file://，Origin 是字面量 null', () => {
    expect(allowedComicOrigin('null', DEV)).toBe('null')
    expect(allowedComicOrigin('null', undefined)).toBe('null')
  })

  it('开发模式只放行 electron-vite 自己的地址', () => {
    expect(allowedComicOrigin(DEV, DEV)).toBe(DEV)
    expect(allowedComicOrigin('http://localhost:5173', 'http://localhost:5173/index.html')).toBe(
      'http://localhost:5173'
    )
    expect(allowedComicOrigin('http://localhost:9999', DEV)).toBeNull()
  })

  it('任何外部来源都不放行', () => {
    for (const origin of [
      'https://evil.example',
      'http://127.0.0.1:5173', // 与 localhost 不同源
      'file://',
      'app://x'
    ]) {
      expect(allowedComicOrigin(origin, DEV)).toBeNull()
    }
  })

  it('没有开发地址时（打包环境）只认 null', () => {
    expect(allowedComicOrigin(DEV, undefined)).toBeNull()
    expect(allowedComicOrigin('https://evil.example', undefined)).toBeNull()
  })

  it('开发地址本身非法时不放行，也不抛错', () => {
    expect(allowedComicOrigin(DEV, '不是一个 URL')).toBeNull()
  })
})

describe('comicRef', () => {
  it('只取 id 前 8 位，不带标题', () => {
    expect(comicRef('0f8c1e2a-1234-5678-9abc-def012345678')).toBe('#0f8c1e2a')
    expect(comicRef('short')).toBe('#short')
  })
})

describe('redactPath', () => {
  it('保留盘符、层数与扩展名，去掉具体名字', () => {
    expect(redactPath('D:\\comics\\作者A\\第01卷.cbz')).toBe('D:\\…2层\\*.cbz')
    expect(redactPath('D:/comics/作者A/第01卷.cbz')).toBe('D:\\…2层\\*.cbz')
  })

  it('不泄露用户名', () => {
    const out = redactPath('C:\\Users\\dafu1\\AppData\\Roaming\\app\\downloads\\某本漫画')
    expect(out).toBe('C:\\…6层\\*')
    expect(out).not.toContain('dafu1')
    expect(out).not.toContain('某本漫画')
  })

  it('UNC 与 posix 路径', () => {
    expect(redactPath('\\\\NAS\\share\\a\\b.zip')).toBe('\\\\…3层\\*.zip')
    expect(redactPath('/home/someone/comics/x.rar')).toBe('/…3层\\*.rar')
  })

  it('根目录下的文件与相对路径', () => {
    expect(redactPath('D:\\a.zip')).toBe('D:\\*.zip')
    expect(redactPath('D:\\')).toBe('D:\\*')
    expect(redactPath('x.cbz')).toBe('*.cbz')
    expect(redactPath('sub/x.cbz')).toBe('…1层\\*.cbz')
  })

  it('空路径不炸', () => {
    expect(redactPath('')).toBe('(空路径)')
  })
})

describe('SourceError 的日志文案', () => {
  it('界面拿到完整路径，日志里只剩路径形状', () => {
    const raw = 'D:\\comics\\某部作品'
    const err = new SourceError(`文件夹不存在，可能已被移动或删除：${raw}`, raw)
    // 给用户看的原文要保留完整路径，否则没法定位是哪个文件
    expect(err.message).toContain(raw)
    expect(err.logMessage).toBe('文件夹不存在，可能已被移动或删除：D:\\…1层\\*')
    expect(err.logMessage).not.toContain('某部作品')
  })

  it('没有附带路径的错误原样返回', () => {
    expect(new SourceError('压缩包已损坏').logMessage).toBe('压缩包已损坏')
  })
})
