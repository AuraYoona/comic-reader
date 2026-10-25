import SwiftUI
import ComicReaderCore
import UIKit

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
    private final class BusState: @unchecked Sendable {
        var autoPos: CGFloat = -1
        var tokens: [NSObjectProtocol] = []
        /// 宿主 UIScrollView 缓存（主线程访问）：几何回调高频触发，
        /// 不能每次都递归遍历视图树去找
        weak var host: UIScrollView?
    }

    @State private var heights: [Int: CGFloat] = [:]
    @State private var busState = BusState()
    /// 最近一次由滚动位置上报的页码（对齐桌面版 lastReported ref）：
    /// onChange 消费时用它区分「滚动自身翻页」与「外部跳页」
    @State private var lastReportedPage = -1
    /// 各槽位在内容坐标里的绝对 Y（minY + 回调时刻的 contentOffset）。
    /// 绝对 Y 只随布局变化移动、不随滚动漂移——闭环定位的实测输入
    @State private var slotAbsoluteY: [Int: CGFloat] = [:]
    /// 非 nil = 正在把视口定位到该页（中线闸关闭）；nil = 闸开，页码跟随视口
    @State private var positioningTarget: Int?
    /// 上一轮程序性滚动的锚点 offset。nil = 尚未锚定，差值检测跳过
    /// （自举 scrollTo 的位移不能被误判成用户接管）
    @State private var programmaticOffset: CGFloat?
    @State private var positioningWork: [DispatchWorkItem] = []
    /// 锚定补偿开关（视口上方行长高时顶回 offset，等价 CSS overflow
    /// anchoring）；真机若出现异常位移可单独关闭
    private let anchorCompensationEnabled = true

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
                .onAppear {
                    // 恢复上次阅读位置：闭环定位（对齐桌面版 mount 的
                    // scrollIntoView，但落点由实测帧决定，与懒加载的高度
                    // 估算无关——估算对条漫差 3~10 倍，scrollTo 必偏）
                    if reader.page > 0 {
                        beginPositioning(to: reader.page, proxy: proxy)
                    }
                }
                .onDisappear {
                    cancelPositioningWork()
                }
                .onChange(of: reader.page) { newPage in
                    // 外部跳页（进度条 / 缩略图条 / 书签）→ 同样走闭环定位。
                    // 先消费 lastReportedPage（对齐桌面版 ScrollView.tsx:104），
                    // 否则「跳回最近上报过的页」会被误判为滚动自身而吞掉
                    if newPage != lastReportedPage {
                        beginPositioning(to: newPage, proxy: proxy)
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
                        guard w > 0 else { return }
                        applyNaturalSize(index: index, width: width, ratio: h / w)
                    },
                    onSettled: nil
                )
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
        // 页码侦测挂在 Group 上：占位与图片槽都要能上报。只挂图片分支时，
        // 快甩越过 ±2 挂载窗后视口全是无上报器的占位槽，页码与窗口双双
        // 冻结（灰屏 + 页码卡死的死锁来源）；桌面版 currentObs 观察全部槽位
        .background(midlineReporter(index: index, viewportHeight: viewportHeight))
    }

    /// 图片真实宽高比到手：记高度；视口上方的行长高时做锚定补偿
    /// （SwiftUI 没有 CSS overflow anchoring，不补偿则内容整体后移、视口被顶回）
    private func applyNaturalSize(index: Int, width: CGFloat, ratio: Double) {
        let newHeight = width * ratio
        let oldHeight = heights[index] ?? max(420, width * 1.2)
        guard newHeight != oldHeight else { return }
        heights[index] = newHeight
        if positioningTarget != nil {
            // 定位中：目标附近高度在变，追加一轮事件驱动的闭环校正
            scheduleExtraPositioningRound()
            return
        }
        guard anchorCompensationEnabled,
              let host = hostScrollView(),
              !host.isTracking, !host.isDragging, !host.isDecelerating,
              let absY = slotAbsoluteY[index],
              absY < host.contentOffset.y - 8  // 行顶在视口上方
        else { return }
        let dy = newHeight - oldHeight
        host.setContentOffset(
            CGPoint(x: 0, y: Self.clampOffset(host.contentOffset.y + dy, for: host)),
            animated: false
        )
    }

    /// 槽位几何回调：记录绝对 Y（闭环定位的实测输入）+ 页码闸门判定
    private func observeSlot(index: Int, frame: CGRect, viewportHeight: CGFloat) {
        guard let host = hostScrollView() else {
            if positioningTarget == nil {
                reportMidline(index: index, frame: frame, viewportHeight: viewportHeight)
            }
            return
        }
        slotAbsoluteY[index] = frame.minY + host.contentOffset.y
        guard positioningTarget != nil else {
            reportMidline(index: index, frame: frame, viewportHeight: viewportHeight)
            return
        }
        // 闸关：只有「视口被用户 / 自动滚动带走」才开闸（手势三旗，或相对
        // 程序锚点漂移 >48pt）。UIKit 在 contentSize 收缩时会把 offset 钳到
        // 边界——恰好贴住 0/maxOffset 是钳制特征，重同步而非判接管。
        // 定位失败且用户未动时保持闸关：page 维持恢复目标入库，不写错页
        if host.isTracking || host.isDragging || host.isDecelerating {
            finishPositioning()
            return
        }
        if let prog = programmaticOffset, abs(host.contentOffset.y - prog) > 48 {
            let maxOffset = max(0, host.contentSize.height - host.bounds.height)
            let clampedToEdge = host.contentOffset.y <= 1 || abs(host.contentOffset.y - maxOffset) <= 1
            if clampedToEdge {
                programmaticOffset = host.contentOffset.y
            } else {
                finishPositioning()
            }
        }
    }

    /// 页中线交叉检测：包含视口中线的槽位成为当前页
    private func midlineReporter(index: Int, viewportHeight: CGFloat) -> some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .named("readerScroll"))
            Color.clear
                .onAppear { observeSlot(index: index, frame: frame, viewportHeight: viewportHeight) }
                .onChange(of: frame.minY) { _ in
                    observeSlot(index: index, frame: frame, viewportHeight: viewportHeight)
                }
                .onChange(of: frame.maxY) { _ in
                    observeSlot(index: index, frame: frame, viewportHeight: viewportHeight)
                }
        }
    }

    private func reportMidline(index: Int, frame: CGRect, viewportHeight: CGFloat) {
        guard viewportHeight > 0 else { return }
        let mid = viewportHeight / 2
        guard frame.minY <= mid, frame.maxY >= mid else { return }
        // 先记录再判定：视口与 reader.page 一致时也要同步 lastReportedPage，
        // 否则「外部跳回最近上报过的页」会被误判成滚动自身而漏滚
        lastReportedPage = index
        guard reader.page != index else { return }
        reader.setPage(index)
    }

    // MARK: 滚动总线（scrollBus.ts 的移植）

    // MARK: 恢复 / 跳页定位（闭环实测，与懒加载的高度估算无关）
    //
    // scrollTo 对懒栈里未物化的行只能按内部估算落点（条漫真实页高是估算的
    // 3~10 倍，必偏）。这里 scrollTo 只负责「自举物化目标行」，落点由实测帧
    // 决定：槽位几何回调记录每行的绝对 Y，定位轮把 contentOffset 直接设到
    // 「目标行顶贴视口顶」。定位期间（闸关）中线不上报页码——定位失败且
    // 用户未动时 page 保持恢复目标入库，绝不写错页；用户的第一个手势开闸。

    /// 开始闭环定位：恢复位置 / 外部跳页共用
    private func beginPositioning(to target: Int, proxy: ScrollViewProxy) {
        cancelPositioningWork()
        positioningTarget = target
        programmaticOffset = nil
        lastReportedPage = target
        // iOS 16 首帧布局完成前 scrollTo 可能被丢弃：推迟到下一 runloop 发
        DispatchQueue.main.async { proxy.scrollTo(target, anchor: .top) }
        for delay in [0.35, 0.9, 1.6, 2.6] {
            scheduleRound(after: delay) { [proxy] in
                self.positioningStep(target: target, proxy: proxy)
            }
        }
    }

    /// 定位中的高度变化（图片解码完成）追加一轮事件驱动的校正
    private func scheduleExtraPositioningRound() {
        guard let target = positioningTarget else { return }
        scheduleRound(after: 0.15) {
            self.positioningStep(target: target, proxy: nil)
        }
    }

    private func scheduleRound(after delay: TimeInterval, _ step: @escaping @Sendable () -> Void) {
        let item = DispatchWorkItem(block: step)
        positioningWork.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func positioningStep(target: Int, proxy: ScrollViewProxy?) {
        guard positioningTarget == target else { return }
        guard let host = hostScrollView() else { return }
        // 收敛：实测绝对 Y 与当前 offset 对齐（上一轮设完后未再漂移）
        if let absY = slotAbsoluteY[target], abs(absY - host.contentOffset.y) <= 24 {
            finishPositioning()
            return
        }
        // 手势接管 → 开闸，页码从用户实际位置自愈
        if host.isTracking || host.isDragging || host.isDecelerating {
            finishPositioning()
            return
        }
        guard let absY = slotAbsoluteY[target] else {
            // 目标行尚未物化：scrollTo 自举（估算落点不准无妨，只为物化）。
            // 不写 programmaticOffset——自举位移不得被误判成用户接管
            proxy?.scrollTo(target, anchor: .top)
            return
        }
        let desired = Self.clampOffset(absY, for: host)
        host.setContentOffset(CGPoint(x: 0, y: desired), animated: false)
        programmaticOffset = desired
    }

    private func finishPositioning() {
        positioningTarget = nil
        programmaticOffset = nil
        cancelPositioningWork()
    }

    private func cancelPositioningWork() {
        for item in positioningWork { item.cancel() }
        positioningWork.removeAll()
    }

    /// 宿主 UIScrollView（带缓存）：几何回调高频触发，不能每次遍历视图树
    private func hostScrollView() -> UIScrollView? {
        if let cached = busState.host { return cached }
        let found = Self.findScrollView()
        if let found { busState.host = found }
        return found
    }

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

    /// 找到承载阅读内容的 UIScrollView（SwiftUI ScrollView 的宿主）。
    /// 只认「纵向可滚动」的：缩略图条等横向滚动视图会被排除，
    /// 避免把所有滚动命令打到错误的视图上。
    private static func findScrollView() -> UIScrollView? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return nil }
        func find(_ view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView,
               scroll.contentSize.height > scroll.bounds.height + 1 {
                return scroll
            }
            for sub in view.subviews {
                if let found = find(sub) { return found }
            }
            return nil
        }
        return find(window)
    }
}
