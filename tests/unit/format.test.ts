import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { basename, readPercent, relativeTime } from '../../src/renderer/src/utils/format'

describe('readPercent', () => {
  it('未读返回 0', () => {
    expect(readPercent(null, 5, 100)).toBe(0)
  })
  it('正常计算并四舍五入', () => {
    expect(readPercent(1, 0, 100)).toBe(1) // 第 1 页 / 100
    expect(readPercent(1, 49, 100)).toBe(50)
  })
  it('读到最后一页为 100，且不会超过 100', () => {
    expect(readPercent(1, 99, 100)).toBe(100)
    expect(readPercent(1, 150, 100)).toBe(100)
  })
  it('页数为 0 时返回 0（不产生 NaN）', () => {
    expect(readPercent(1, 0, 0)).toBe(0)
  })
})

describe('relativeTime', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-07-13T12:00:00'))
  })
  afterEach(() => {
    vi.useRealTimers()
  })

  it('空值显示未读', () => {
    expect(relativeTime(null)).toBe('未读')
  })
  it('分级显示', () => {
    const now = Date.now()
    expect(relativeTime(now - 10_000)).toBe('刚刚')
    expect(relativeTime(now - 5 * 60_000)).toBe('5 分钟前')
    expect(relativeTime(now - 3 * 3_600_000)).toBe('3 小时前')
    expect(relativeTime(now - 2 * 86_400_000)).toBe('2 天前')
  })
  it('超过 30 天显示日期', () => {
    expect(relativeTime(Date.now() - 40 * 86_400_000)).toBe('2026-06-03')
  })
})

describe('basename', () => {
  it('兼容两种分隔符', () => {
    expect(basename('C:\\a\\b\\c.zip')).toBe('c.zip')
    expect(basename('/home/x/y.cbz')).toBe('y.cbz')
    expect(basename('plain')).toBe('plain')
  })
})
