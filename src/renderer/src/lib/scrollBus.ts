/**
 * 连续滚动视图挂载时把「按视口比例滚动」的方法注册到这里。
 *
 * 键盘（空格 / 方向键 / PgUp / PgDn）与自动翻页都需要驱动滚动容器，
 * 但它们分别住在 Reader 与阅读器 store 里，用一个极小的模块级出口最省事。
 */
export const scrollBus: { scrollByViewport: ((fraction: number) => void) | null } = {
  scrollByViewport: null
}
