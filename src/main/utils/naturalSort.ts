/**
 * 自然排序：让 "1.jpg, 2.jpg, 10.jpg" 按数值顺序排列，
 * 同时兼容中文等本地化字符。
 */
const collator = new Intl.Collator(['zh', 'en'], {
  numeric: true,
  sensitivity: 'base'
})

export function naturalCompare(a: string, b: string): number {
  return collator.compare(a, b)
}

export function naturalSort(items: string[]): string[] {
  return [...items].sort(naturalCompare)
}
