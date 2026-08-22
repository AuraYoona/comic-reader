import { describe, expect, it } from 'vitest'
import {
  isLastSpread,
  isWideSize,
  spreadAt,
  stepSpread,
  type SpreadContext
} from '../../src/shared/paging'

/** offset=1：封面单独占屏，之后 (1,2) (3,4)… 成对 */
const cover: SpreadContext = { pageCount: 10, offset: 1 }
/** offset=0：从第一页起两两成对 */
const paired: SpreadContext = { pageCount: 10, offset: 0 }

describe('spreadAt', () => {
  it('封面单独占屏，之后两两成对', () => {
    expect(spreadAt(0, cover)).toEqual([0])
    expect(spreadAt(1, cover)).toEqual([1, 2])
    expect(spreadAt(2, cover)).toEqual([1, 2])
    expect(spreadAt(3, cover)).toEqual([3, 4])
  })

  it('offset=0 时从第一页起配对', () => {
    expect(spreadAt(0, paired)).toEqual([0, 1])
    expect(spreadAt(1, paired)).toEqual([0, 1])
    expect(spreadAt(2, paired)).toEqual([2, 3])
  })

  it('最后一页落单时自己占一屏', () => {
    const odd: SpreadContext = { pageCount: 4, offset: 1 }
    expect(spreadAt(3, odd)).toEqual([3])
  })

  it('跨页图独占整屏，并让后续配对顺延', () => {
    const ctx: SpreadContext = { pageCount: 8, offset: 1, isWide: (i) => i === 3 }
    expect(spreadAt(1, ctx)).toEqual([1, 2])
    expect(spreadAt(3, ctx)).toEqual([3])
    // 跨页把节奏推后一位：原本的 (3,4) 变成 (4,5)
    expect(spreadAt(4, ctx)).toEqual([4, 5])
    expect(spreadAt(6, ctx)).toEqual([6, 7])
  })

  it('跨页图不会被拉进别人的一屏', () => {
    const ctx: SpreadContext = { pageCount: 6, offset: 0, isWide: (i) => i === 1 }
    expect(spreadAt(0, ctx)).toEqual([0])
    expect(spreadAt(1, ctx)).toEqual([1])
    expect(spreadAt(2, ctx)).toEqual([2, 3])
  })

  it('页码越界会被夹回范围内，空书返回空数组', () => {
    expect(spreadAt(999, cover)).toEqual([9])
    expect(spreadAt(-5, cover)).toEqual([0])
    expect(spreadAt(0, { pageCount: 0, offset: 1 })).toEqual([])
  })
})

describe('stepSpread', () => {
  it('按屏前进与后退', () => {
    expect(stepSpread(0, 1, cover)).toBe(1)
    expect(stepSpread(1, 1, cover)).toBe(3)
    expect(stepSpread(3, -1, cover)).toBe(1)
    expect(stepSpread(1, -1, cover)).toBe(0)
  })

  it('已在首屏 / 末屏时停在原地', () => {
    expect(stepSpread(0, -1, cover)).toBe(0)
    const last = { pageCount: 5, offset: 1 } // 屏：[0] [1,2] [3,4]
    expect(stepSpread(4, 1, last)).toBe(3)
  })

  it('跨页图参与步进', () => {
    const ctx: SpreadContext = { pageCount: 8, offset: 1, isWide: (i) => i === 3 }
    expect(stepSpread(1, 1, ctx)).toBe(3)
    expect(stepSpread(3, 1, ctx)).toBe(4)
    expect(stepSpread(4, -1, ctx)).toBe(3)
  })

  it('空书不崩', () => {
    expect(stepSpread(0, 1, { pageCount: 0, offset: 0 })).toBe(0)
  })
})

describe('isLastSpread', () => {
  it('覆盖到最后一页就算最后一屏', () => {
    expect(isLastSpread(9, cover)).toBe(true)
    expect(isLastSpread(7, cover)).toBe(false)
    // 10 页 + 封面单独：最后一屏是 [9]
    expect(isLastSpread(8, cover)).toBe(false)
  })

  it('空书当作已到尽头', () => {
    expect(isLastSpread(0, { pageCount: 0, offset: 1 })).toBe(true)
  })
})

describe('isWideSize', () => {
  it('横向明显更宽才算跨页', () => {
    expect(isWideSize(2000, 1400)).toBe(true)
    expect(isWideSize(1400, 2000)).toBe(false)
    expect(isWideSize(1000, 1000)).toBe(false)
    expect(isWideSize(0, 0)).toBe(false)
  })
})
