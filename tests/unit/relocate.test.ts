import { describe, expect, it } from 'vitest'
import { buildNameIndex, pickMatch, toIndexedEntry } from '../../src/main/utils/relocate'

const index = buildNameIndex(
  [
    'E:/漫画/作者A/第01卷',
    'E:/漫画/作者A/第02卷',
    'E:/漫画/作者B/第01卷',
    'E:/漫画/单行本/孤独摇滚.cbz'
  ].map(toIndexedEntry)
)

describe('toIndexedEntry', () => {
  it('拆出名字与父目录名', () => {
    expect(toIndexedEntry('E:/漫画/作者A/第01卷')).toEqual({
      path: 'E:/漫画/作者A/第01卷',
      name: '第01卷',
      parent: '作者A'
    })
  })
})

describe('pickMatch', () => {
  it('按文件（夹）名精确匹配', () => {
    expect(pickMatch('D:/old/单行本/孤独摇滚.cbz', index)).toBe('E:/漫画/单行本/孤独摇滚.cbz')
  })

  it('同名有多个时优先父目录也一致的那个', () => {
    expect(pickMatch('D:/backup/作者B/第01卷', index)).toBe('E:/漫画/作者B/第01卷')
    expect(pickMatch('D:/backup/作者A/第01卷', index)).toBe('E:/漫画/作者A/第01卷')
  })

  it('父目录对不上时退回第一个同名项', () => {
    expect(pickMatch('D:/别处/未知作者/第01卷', index)).toBe('E:/漫画/作者A/第01卷')
  })

  it('找不到就返回 null，绝不乱猜', () => {
    expect(pickMatch('D:/old/不存在的作品', index)).toBeNull()
    expect(pickMatch('', index)).toBeNull()
  })

  it('大小写不敏感（Windows 搬盘常伴随大小写变化）', () => {
    const ci = buildNameIndex([toIndexedEntry('E:/lib/Vol01.cbz')])
    expect(pickMatch('D:/old/VOL01.CBZ', ci)).toBe('E:/lib/Vol01.cbz')
  })

  it('反斜杠与正斜杠的旧路径都能拆', () => {
    expect(pickMatch('D:\\old\\作者B\\第01卷', index)).toBe('E:/漫画/作者B/第01卷')
  })

  it('末尾多余的分隔符不影响匹配', () => {
    expect(pickMatch('D:/old/作者B/第01卷/', index)).toBe('E:/漫画/作者B/第01卷')
  })
})

describe('buildNameIndex', () => {
  it('同名项按发现顺序聚在一起', () => {
    const built = buildNameIndex(['A/x', 'B/x', 'C/y'].map((p) => toIndexedEntry(p)))
    expect(built.get('x')?.map((e) => e.parent)).toEqual(['A', 'B'])
    expect(built.get('y')).toHaveLength(1)
    expect(built.get('缺失')).toBeUndefined()
  })
})
