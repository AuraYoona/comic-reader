import SwiftUI
import ComicReaderCore

// MARK: - 翻页视图：单页 / 双页（PagedView.tsx 的移植）
//
// 交互映射（桌面 → 触屏）：
//   点按分区（<0.32 / >0.68 / 中间）→ 同样的三分区 tap；尊重 RTL
//   Ctrl+滚轮缩放 → 双指捏合；放大后拖拽平移；双击 = 重置缩放
//   鼠标侧键 / 滚轮边缘翻页 → 底栏按钮 / tap 分区
// 翻到新一屏：前进滚回顶部、后退停在底部（阅读直觉，对齐桌面）。

struct PagedView: View {
    @EnvironmentObject private var reader: ReaderStore
    @EnvironmentObject private var settings: SettingsStore

    /// 中间分区点按 → 切换工具条（由 ReaderView 传入）
    let onToggleBars: () -> Void

    /// 双页模式页间 8pt（PAGE_GAP）
    private static let pageGap: CGFloat = 8

    @State private var viewportSize: CGSize = .zero
    @State private var manualScale: Double = 1
    @State private var settledPages: Set<Int> = []

    var body: some View {
        GeometryReader { geo in
            let box = geo.size
            Group {
                if reader.mode == .double {
                    doublePage(box: box)
                } else {
                    singlePage(box: box)
                }
            }
            .frame(width: box.width, height: box.height)
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleTap(at: location, width: box.width)
            }
            .simultaneousGesture(zoomGesture(box: box))
            .onAppear { viewportSize = box }
            .onChange(of: geo.size) { viewportSize = $0 }
        }
        .task(id: reader.comic?.id) {
            await readerSettle()
        }
        .onChange(of: reader.page) { _ in
            // 每次翻页预取邻页（对齐 PagedView.tsx 的 prefetch 邻域）
            reader.prefetchNeighbors(maxPixelSize: prefetchPixelSize)
        }
    }

    private var effectiveScale: Double {
        ZoomLimits.clampScale(reader.scale * manualScale)
    }

    // MARK: 页面渲染

    @ViewBuilder
    private func singlePage(box: CGSize) -> some View {
        if let comic = reader.comic, reader.pageCount > 0 {
            pageView(comic: comic, index: min(reader.page, reader.pageCount - 1), box: box)
        }
    }

    @ViewBuilder
    private func doublePage(box: CGSize) -> some View {
        if let comic = reader.comic {
            let spread = reader.currentSpread
            let half = max(60, (box.width - Self.pageGap) / 2)
            let halfBox = CGSize(width: half, height: box.height)

            HStack(spacing: Self.pageGap) {
                ForEach(Array(pagesInOrder(spread).enumerated()), id: \.element) { _, index in
                    pageView(comic: comic, index: index, box: halfBox)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// RTL 时视觉反序（对齐 row-reverse；数组本身仍是升序页码）
    private func pagesInOrder(_ spread: [Int]) -> [Int] {
        reader.direction == .rtl ? spread.reversed() : spread
    }

    @ViewBuilder
    private func pageView(comic: Comic, index: Int, box: CGSize) -> some View {
        PageImageView(
            comic: comic,
            index: index,
            boxSize: box,
            mode: reader.zoom,
            scale: effectiveScale,
            autoCrop: reader.autoCrop,
            onNatural: { w, h in
                reader.markWide(index, isWide: isWideSize(width: w, height: h))
            },
            onSettled: { settledPages.insert(index) }
        )
    }

    // MARK: 手势

    /// 三分区点按（0.32 / 0.68 阈值与桌面一致）；中间 = 切工具条
    private func handleTap(at location: CGPoint, width: CGFloat) {
        let ratio = location.x / width
        let goNext = reader.direction == .ltr ? ratio > 0.68 : ratio < 0.32
        let goPrev = reader.direction == .ltr ? ratio < 0.32 : ratio > 0.68

        if goNext {
            reader.next()
        } else if goPrev {
            reader.prev()
        } else {
            onToggleBars() // 中间分区：切换工具条（对齐桌面的中间点击）
        }
    }

    /// 双指捏合缩放（对齐 Ctrl+滚轮的 0.25–4）；结束后落回 reader.scale（持久化）
    private func zoomGesture(box: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                manualScale = value
            }
            .onEnded { value in
                let combined = ZoomLimits.clampScale(reader.scale * value)
                manualScale = 1
                reader.setScale(combined)
            }
    }

    private func readerSettle() async {
        settledPages.removeAll()
        reader.prefetchNeighbors(maxPixelSize: prefetchPixelSize)
    }

    private var prefetchPixelSize: Int {
        let width = max(viewportSize.width, 320)
        return min(4096, max(1024, Int(width * UIScreen.main.scale * 2)))
    }
}
