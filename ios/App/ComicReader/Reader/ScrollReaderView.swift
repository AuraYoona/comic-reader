import SwiftUI
import ComicReaderCore

// MARK: - 连续滚动（条漫）视图（ScrollView.tsx 的移植）
//
// 挂载策略：只挂载当前页 ±2 页（条漫页高约一屏，近似桌面版的 ±2 屏 LOAD_MARGIN），
// 远处用占位并记忆最近已知高度，回滚不跳变；跨视口中线的那页 = 当前页
// （CURRENT_BAND -45%/-54.9% 的语义）。
// 滚动总线：ReaderView（自动翻页 / 平滑滚动）经 NotificationCenter 驱动本视图。

struct ScrollReaderView: View {
    @EnvironmentObject private var reader: ReaderStore

    /// 点按（非拖动）→ 切换工具条（由 ReaderView 传入）
    let onToggleBars: () -> Void

    /// 浮点累加器（平滑滚动的绝对位置；用户手动滚动时自动对齐）+ 观察者 token
    private final class BusState {
        var autoPos: CGFloat = -1
        var tokens: [NSObjectProtocol] = []
    }

    @State private var heights: [Int: CGFloat] = [:]
    @State private var busState = BusState()
    @State private var suppressMidlineReport = false

    var body: some View {
        GeometryReader { geo in
            let viewportHeight = geo.size.height
            let width = geo.size.width
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 4) {
                        if let comic = reader.comic {
                            ForEach(0..<max(reader.pageCount, 0), id: \.self) { index in
                                slot(comic: comic, index: index, width: width, viewportHeight: viewportHeight)
                                    .id(index)
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
                .coordinateSpace(name: "readerScroll")
                .simultaneousGesture(
                    // 轻点（非拖动）切工具条；拖动滚动不受影响
                    TapGesture().onEnded { onToggleBars() }
                )
                .onChange(of: reader.page) { newPage in
                    // 外部跳页（进度条 / 缩略图条 / 书签）→ 滚到该页顶部
                    if !suppressMidlineReport {
                        proxy.scrollTo(newPage, anchor: .top)
                    }
                }
            }
        }
        .onAppear(perform: bindScrollBus)
        .onDisappear(perform: unbindScrollBus)
    }

    // MARK: 槽位

    @ViewBuilder
    private func slot(comic: Comic, index: Int, width: CGFloat, viewportHeight: CGFloat) -> some View {
        let visible = abs(index - reader.page) <= 2
        let placeholderHeight = heights[index] ?? max(420, width * 1.2)

        Group {
            if visible {
                PageImageView(
                    comic: comic,
                    index: index,
                    boxSize: CGSize(width: width, height: placeholderHeight),
                    mode: reader.zoom,
                    scale: min(reader.scale, 1),
                    autoCrop: reader.autoCrop,
                    onNatural: { w, h in
                        // 记录真实高度（按适宽估算），卸载后占位高度不跳
                        if w > 0 {
                            heights[index] = width * (h / w)
                        }
                    },
                    onSettled: nil
                )
                .background(midlineReporter(index: index, viewportHeight: viewportHeight))
            } else {
                ZStack {
                    Color(uiColor: .secondarySystemBackground).opacity(0.35)
                    Text("第 \(index + 1) 页")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: placeholderHeight)
            }
        }
    }

    /// 页中线交叉检测：包含视口中线的槽位成为当前页
    private func midlineReporter(index: Int, viewportHeight: CGFloat) -> some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .named("readerScroll"))
            Color.clear
                .onAppear { reportMidline(index: index, frame: frame, viewportHeight: viewportHeight) }
                .onChange(of: frame.minY) { _ in
                    reportMidline(index: index, frame: frame, viewportHeight: viewportHeight)
                }
                .onChange(of: frame.maxY) { _ in
                    reportMidline(index: index, frame: frame, viewportHeight: viewportHeight)
                }
        }
    }

    private func reportMidline(index: Int, frame: CGRect, viewportHeight: CGFloat) {
        guard viewportHeight > 0 else { return }
        let mid = viewportHeight / 2
        guard frame.minY <= mid, frame.maxY >= mid else { return }
        guard reader.page != index else { return }
        suppressMidlineReport = true
        reader.setPage(index)
        suppressMidlineReport = false
    }

    // MARK: 滚动总线（scrollBus.ts 的移植）

    private func bindScrollBus() {
        guard busState.tokens.isEmpty else { return }
        let center = NotificationCenter.default
        let viewportToken = center.addObserver(
            forName: .readerScrollByViewport, object: nil, queue: .main
        ) { note in
            let fraction = note.userInfo?["fraction"] as? CGFloat ?? 0
            guard let scroll = Self.findScrollView() else { return }
            let target = scroll.contentOffset.y + scroll.bounds.height * fraction
            scroll.setContentOffset(
                CGPoint(x: 0, y: Self.clampOffset(target, for: scroll)), animated: true
            )
        }
        let pixelsToken = center.addObserver(
            forName: .readerScrollByPixels, object: nil, queue: .main
        ) { [busState] note in
            let dy = note.userInfo?["dy"] as? CGFloat ?? 0
            let completion = note.userInfo?["completion"] as? (Bool) -> Void
            guard let scroll = Self.findScrollView() else {
                completion?(false)
                return
            }
            let current = scroll.contentOffset.y
            // 用户手动滚动过（与累加器偏差 > 2pt）→ 重新对齐
            if busState.autoPos < 0 || abs(current - busState.autoPos) > 2 {
                busState.autoPos = current
            }
            busState.autoPos += dy
            let maxOffset = max(0, scroll.contentSize.height - scroll.bounds.height)
            let target = min(max(0, busState.autoPos), maxOffset)
            scroll.setContentOffset(CGPoint(x: 0, y: target), animated: false)
            completion?(target >= maxOffset - 1)
        }
        busState.tokens = [viewportToken, pixelsToken]
    }

    private func unbindScrollBus() {
        let center = NotificationCenter.default
        for token in busState.tokens {
            center.removeObserver(token)
        }
        busState.tokens.removeAll()
    }

    private static func clampOffset(_ y: CGFloat, for scroll: UIScrollView) -> CGFloat {
        let maxOffset = max(0, scroll.contentSize.height - scroll.bounds.height)
        return min(max(0, y), maxOffset)
    }

    /// 找到承载阅读内容的 UIScrollView（SwiftUI ScrollView 的宿主）
    private static func findScrollView() -> UIScrollView? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return nil }
        func find(_ view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView { return scroll }
            for sub in view.subviews {
                if let found = find(sub) { return found }
            }
            return nil
        }
        return find(window)
    }
}
