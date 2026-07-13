import { describe, expect, it } from 'vitest'
import { naturalCompare, naturalSort } from '../../src/main/utils/naturalSort'

describe('naturalSort', () => {
  it('按数值排序而非字典序：1、2、10', () => {
    expect(naturalSort(['10.jpg', '1.jpg', '2.jpg'])).toEqual(['1.jpg', '2.jpg', '10.jpg'])
  })

  it('处理前导零与多段数字', () => {
    expect(naturalSort(['p002.png', 'p1.png', 'p010.png'])).toEqual([
      'p1.png',
      'p002.png',
      'p010.png'
    ])
    expect(naturalSort(['ch2/5.jpg', 'ch2/10.jpg', 'ch10/1.jpg', 'ch1/1.jpg'])).toEqual([
      'ch1/1.jpg',
      'ch2/5.jpg',
      'ch2/10.jpg',
      'ch10/1.jpg'
    ])
  })

  it('大小写不敏感', () => {
    expect(naturalCompare('A.jpg', 'a.jpg')).toBe(0)
  })

  it('不修改原数组', () => {
    const input = ['2.jpg', '1.jpg']
    naturalSort(input)
    expect(input).toEqual(['2.jpg', '1.jpg'])
  })
})
