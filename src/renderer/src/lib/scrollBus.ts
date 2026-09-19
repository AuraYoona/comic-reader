/**
 * 连续滚动视图挂载时把「按视口比例滚动」的方法注册到这里。
 *
 * 键盘（空格 / 方向键 / PgUp / PgDn）与自动翻页都需要驱动滚动容器，
 * 但它们分别住在 Reader 与阅读器 store 里，用一个极小的模块级出口最省事。
 */
export const scrollBus: {
  scrollByViewport: ((fraction: number) => void) | null
  /**
   * 平滑自动滚动：向下推进 dy 像素（可为小数，条漫的自动滚动每帧调一次）。
   * 返回 false 表示已经到底、没能再滚动。
   */
  scrollByPixels: ((dy: number) => boolean) | null
} = {
  scrollByViewport: null,
  scrollByPixels: null
}
