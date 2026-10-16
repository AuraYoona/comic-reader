import SwiftUI
import ComicReaderCore

// MARK: - 阅读器顶层（Reader.tsx 的移植）
//
// 打开中 / 失败态覆盖层；模式分派（单双页 → PagedView，滚动 → ScrollReaderView）；
// 自动翻页（定时跳屏或平滑滚动）；工具条自动隐藏（2600ms）；亮度遮罩；
// 「已是最后一页」提示（2600ms 内再触发一次返回书架）。

struct ReaderView: View {
    @EnvironmentObject private var reader: ReaderStore
    @EnvironmentObject private var settings: SettingsStore

    /// 工具条自动隐藏延迟（对齐 Reader.tsx BARS_HIDE_DELAY_MS = 2600）
    private static let barsHideNs: UInt64 = 2_600_000_000
    private static let autoTickNs: UInt64 = 100_000_000

    @State private var barsVisible = true
    @State private var barsTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            contentLayer

            brightnessOverlay

            if reader.opening {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("正在打开…")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }

            if let error = reader.error {
                VStack(spacing: 14) {
                    Image(systemName: "photo")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button("返回书架") { reader.close() }
                        .buttonStyle(.borderedProminent)
                }
            }

            if reader.endHint {
                VStack(spacing: 4) {
                    Text("已是最后一页")
                        .font(.system(size: 15, weight: .semibold))
                    Text("再翻一次返回书架")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    Capsule().fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.3), radius: 14, y: 5)
                )
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 80)
                .transition(.opacity)
                .allowsHitTesting(false)
            }

            bars
        }
        .task(id: autoTurnKey) {
            await runAutoTurn()
        }
        .onAppear {
            // 进入阅读器后工具条自动隐藏计时开始（对齐 Reader.tsx 的 poke 节奏）
            pokeBars()
        }
        .onDisappear {
            barsTask?.cancel()
        }
    }

    // MARK: 内容层

    @ViewBuilder
    private var contentLayer: some View {
        if reader.pageCount > 0, reader.error == nil {
            if reader.mode == .scroll {
                ScrollReaderView(onToggleBars: { toggleBars() })
            } else {
                PagedView(onToggleBars: { toggleBars() })
            }
        }
    }

    /// 亮度遮罩：只压暗页面（1.2 → 白色提亮；工具条不受影响）
    private var brightnessOverlay: View {
        let brightness = settings.settings.brightness
        return ZStack {
            if brightness < 1 {
                Color.black.opacity(1 - brightness).ignoresSafeArea()
            } else if brightness > 1 {
                Color.white.opacity(min(brightness - 1, 0.2)).ignoresSafeArea()
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: 工具条

    private var bars: some View {
        VStack(spacing: 0) {
            if barsVisible {
                ReaderTopBar(onBack: { reader.close() })
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
            if barsVisible {
                ReaderBottomBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.22), value: barsVisible)
    }

    private func toggleBars() {
        withAnimation { barsVisible.toggle() }
        pokeBars()
    }

    private func pokeBars() {
        barsTask?.cancel()
        barsTask = Task { [self] in
            try? await Task.sleep(nanoseconds: Self.barsHideNs)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation { barsVisible = false }
            }
        }
    }

    // MARK: 自动翻页（Reader.tsx 60-89 的移植）

    private var autoTurnKey: String {
        "\(reader.autoTurn)-\(reader.mode)-\(reader.autoScroll)-\(settings.settings.autoTurnSeconds)-\(Int(settings.settings.autoScrollSpeed))-\(reader.active)"
    }

    private func runAutoTurn() async {
        guard reader.active, reader.autoTurn else { return }

        if reader.mode == .scroll && reader.autoScroll {
            // 平滑滚动：CADisplayLink 等价 —— 固定小步长推进，dt 截断 100ms
            let speed = CGFloat(settings.settings.autoScrollSpeed)
            var last = Date()
            while !Task.isCancelled, reader.active, reader.autoTurn {
                let now = Date()
                let dt = min(now.timeIntervalSince(last), 0.1)
                last = now
                ScrollBus.scrollByPixels(speed * dt) { reachedEnd in
                    if reachedEnd {
                        reader.reachEnd()
                        reader.stopAutoTurn()
                    }
                }
                try? await Task.sleep(nanoseconds: Self.autoTickNs)
            }
        } else {
            // 定时翻页 / 跳屏
            while !Task.isCancelled, reader.active, reader.autoTurn {
                try? await Task.sleep(nanoseconds: UInt64(settings.settings.autoTurnSeconds) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                if reader.mode == .scroll {
                    ScrollBus.scrollByViewport(0.85)
                } else {
                    reader.next()
                }
            }
        }
    }
}

// MARK: - 滚动总线（scrollBus.ts 的移植：模块级函数槽）

enum ScrollBus {
    /// 平滑滚动 dy 像素；reachedEnd(true) = 已到底
    static func scrollByPixels(_ dy: CGFloat, completion: ((Bool) -> Void)? = nil) {
        NotificationCenter.default.post(
            name: .readerScrollByPixels,
            object: nil,
            userInfo: ["dy": dy, "completion": completion as Any]
        )
    }

    /// 滚动 fraction 个视口（正 = 向下）
    static func scrollByViewport(_ fraction: CGFloat) {
        NotificationCenter.default.post(
            name: .readerScrollByViewport,
            object: nil,
            userInfo: ["fraction": fraction]
        )
    }
}

extension Notification.Name {
    /// 平滑滚动：dy 像素（滚动视图带浮点累加与到底回执）
    static let readerScrollByPixels = Notification.Name("readerScrollByPixels")
    /// 按视口比例滚动（自动翻页的「按屏翻」与键盘翻屏共用）
    static let readerScrollByViewport = Notification.Name("readerScrollByViewport")
}
