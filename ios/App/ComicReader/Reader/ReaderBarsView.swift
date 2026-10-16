import SwiftUI
import ComicReaderCore

// MARK: - 阅读器顶部工具条（ReaderBars.tsx TopBar 的移植）
//
// 桌面版的全屏按钮在 iOS 上无对应概念，去掉；
// 键盘快捷键（B / T / A / C / O / S / 1 2 3 / [ ]）由底栏按钮承担。

struct ReaderTopBar: View {
    @EnvironmentObject private var reader: ReaderStore
    @EnvironmentObject private var settings: SettingsStore

    let onBack: () -> Void

    @State private var pageDraft = ""
    @FocusState private var jumpFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("书架")
                            .font(.system(size: 14))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                Spacer(minLength: 4)

                if let comic = reader.comic {
                    HStack(spacing: 6) {
                        if let style = comic.style {
                            Text(ComicStyleInfo.label(style))
                                .font(.system(size: 10.5, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                                .foregroundStyle(Color.accentColor)
                        }
                        Text(comic.title)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }

                Spacer(minLength: 4)

                if settings.extensions.bookmarks {
                    bookmarkControls
                }
            }
            .padding(.horizontal, 14)

            jumpRow
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(.bar)
    }

    // MARK: 页码输入跳转（PageJump 的移植）

    private var jumpRow: some View {
        HStack(spacing: 6) {
            TextField("页码", text: $pageDraft)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 13, design: .rounded))
                .frame(width: 56)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                )
                .focused($jumpFocused)
                .onChange(of: reader.page) { _ in
                    if !jumpFocused { pageDraft = "\(reader.page + 1)" }
                }
                .onChange(of: jumpFocused) { focused in
                    if !focused { commitJump() }
                }
                .onSubmit { commitJump() }

            Text("/ \(reader.pageCount)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if reader.mode == .double {
                Text(spreadLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear { pageDraft = "\(reader.page + 1)" }
    }

    /// 双页模式的屏标签（对齐 pageLabel：当前页起两页）
    private var spreadLabel: String {
        let spread = reader.currentSpread
        guard let first = spread.first, let last = spread.last else { return "" }
        return first == last ? "第 \(first + 1) 页" : "第 \(first + 1)–\(last + 1) 页"
    }

    private func commitJump() {
        guard let n = Int(pageDraft), n >= 1 else {
            pageDraft = "\(reader.page + 1)"
            return
        }
        reader.setPage(n - 1)
        pageDraft = "\(reader.page + 1)"
    }

    // MARK: 书签

    private var bookmarkControls: some View {
        HStack(spacing: 2) {
            Button {
                reader.toggleBookmark()
            } label: {
                Image(systemName: reader.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 15))
                    .foregroundStyle(reader.isCurrentPageBookmarked ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(reader.isCurrentPageBookmarked ? "取消本页书签" : "给本页加书签")

            Menu {
                if reader.bookmarks.isEmpty {
                    Text("还没有书签")
                }
                ForEach(reader.bookmarks, id: \.self) { page in
                    Button {
                        reader.setPage(page)
                    } label: {
                        Label(
                            "第 \(page + 1) 页",
                            systemImage: page == reader.page ? "bookmark.fill" : "bookmark"
                        )
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .disabled(reader.bookmarks.isEmpty)
        }
    }
}

// MARK: - 阅读器底部工具条（ReaderBars.tsx BottomBar 的移植）

struct ReaderBottomBar: View {
    @EnvironmentObject private var reader: ReaderStore
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(spacing: 8) {
            if reader.thumbStrip {
                ThumbStripView()
            }

            progressRow
            controlsRow
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }

    // MARK: 进度行

    private var progressRow: some View {
        HStack(spacing: 10) {
            Button {
                reader.direction == .rtl ? reader.next() : reader.prev()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Slider(
                value: progressBinding,
                in: 0...Double(max(reader.pageCount - 1, 1)),
                step: 1
            )

            Button {
                reader.direction == .rtl ? reader.prev() : reader.next()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
    }

    /// RTL 时滑块方向翻转（对齐桌面版 direction: rtl 的滑条）
    private var progressBinding: Binding<Double> {
        Binding(
            get: {
                let p = Double(reader.page)
                return reader.direction == .rtl && reader.mode != .scroll
                    ? Double(max(reader.pageCount - 1, 0)) - p
                    : p
            },
            set: { v in
                let page = reader.direction == .rtl && reader.mode != .scroll
                    ? Double(max(reader.pageCount - 1, 0)) - v
                    : v
                reader.setPage(Int(page))
            }
        )
    }

    // MARK: 控制行（横向滚动承载全部开关）

    private var controlsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                modeControls
                zoomControls
                Divider().frame(height: 18)
                directionControls
                Divider().frame(height: 18)
                autoTurnControls
            }
            .padding(.horizontal, 14)
        }
    }

    private var modeControls: some View {
        HStack(spacing: 4) {
            barButton(icon: "doc", text: "单页", active: reader.mode == .single) {
                reader.setMode(.single)
            }
            barButton(icon: "book", text: "双页", active: reader.mode == .double) {
                reader.setMode(.double)
            }
            barButton(icon: "arrow.down", text: "滚动", active: reader.mode == .scroll) {
                reader.setMode(.scroll)
            }
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Menu {
                Picker("缩放", selection: zoomBinding) {
                    Text("适应宽度").tag(ZoomMode.fitWidth)
                    Text("适应高度").tag(ZoomMode.fitHeight)
                    Text("原始大小").tag(ZoomMode.original)
                }
            } label: {
                compactLabel(zoomLabel)
            }

            barButton(icon: "minus", text: nil, active: false) {
                reader.setScale(reader.scale - 0.1)
            }
            barButton(icon: "plus", text: nil, active: false) {
                reader.setScale(reader.scale + 0.1)
            }
            Button {
                reader.setScale(1)
            } label: {
                Text("\(Int((reader.scale * 100).rounded()))%")
                    .font(.system(size: 12, weight: .medium))
                    .frame(minWidth: 40)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            barButton(icon: "crop", text: "裁边", active: reader.autoCrop) {
                reader.toggleAutoCrop()
            }
            barButton(icon: "film", text: "缩略图", active: reader.thumbStrip) {
                reader.toggleThumbStrip()
            }
        }
    }

    private var zoomBinding: Binding<ZoomMode> {
        Binding(get: { reader.zoom }, set: { reader.setZoom($0) })
    }

    private var zoomLabel: String {
        switch reader.zoom {
        case .fitWidth: return "适宽"
        case .fitHeight: return "适高"
        case .original: return "原始"
        }
    }

    @ViewBuilder
    private var directionControls: some View {
        if reader.mode != .scroll {
            barButton(
                icon: "arrow.left.arrow.right",
                text: reader.direction == .rtl ? "右→左" : "左→右",
                active: reader.direction == .rtl
            ) {
                reader.setDirection(reader.direction == .rtl ? .ltr : .rtl)
            }
        }
        if reader.mode == .double {
            barButton(
                icon: "rectangle.split.2x1",
                text: reader.pageOffset == 1 ? "封面单独" : "首页配对",
                active: reader.pageOffset == 1
            ) {
                reader.togglePageOffset()
            }
        }
        if reader.mode == .scroll {
            barButton(
                icon: "arrow.down.to.line",
                text: reader.autoScroll ? "平滑滚动" : "按屏翻",
                active: reader.autoScroll
            ) {
                reader.toggleAutoScroll()
            }
        }
    }

    // MARK: 自动翻页

    private var autoTurnControls: some View {
        HStack(spacing: 6) {
            barButton(
                icon: reader.autoTurn ? "pause" : "clock",
                text: reader.autoTurn ? "停止" : "自动",
                active: reader.autoTurn
            ) {
                reader.toggleAutoTurn()
            }

            if reader.mode == .scroll && reader.autoScroll {
                // 平滑滚动速度 10–400 px/s，步进 10（[ ] 的等价物）
                stepButton(icon: "minus") {
                    settings.adjustAutoScrollSpeed(by: -AutoScrollLimits.step)
                }
                Text("\(Int(settings.settings.autoScrollSpeed)) px/s")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 62)
                stepButton(icon: "plus") {
                    settings.adjustAutoScrollSpeed(by: AutoScrollLimits.step)
                }
            } else {
                // 自动翻页间隔 2–60 秒（[ ] 的等价物）
                stepButton(icon: "minus") {
                    settings.adjustAutoTurn(by: -1)
                }
                Text("\(settings.settings.autoTurnSeconds) 秒")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44)
                stepButton(icon: "plus") {
                    settings.adjustAutoTurn(by: 1)
                }
            }
        }
    }

    // MARK: 小组件

    private func barButton(
        icon: String, text: String?, active: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                if let text {
                    Text(text)
                        .font(.system(size: 12))
                }
            }
            .foregroundStyle(active ? Color.accentColor : .primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(
                    active ? Color.accentColor.opacity(0.14) : Color(uiColor: .tertiarySystemFill)
                )
            )
        }
        .buttonStyle(.plain)
    }

    private func stepButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color(uiColor: .tertiarySystemFill)))
        }
        .buttonStyle(.plain)
    }

    private func compactLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
    }
}

// MARK: - 缩略图跳页条（ThumbStrip.tsx 的移植：78×108 槽位、当前页居中）

struct ThumbStripView: View {
    @EnvironmentObject private var reader: ReaderStore
    @EnvironmentObject private var pages: PageProvider

    private static let thumbWidth: CGFloat = 78
    private static let thumbHeight: CGFloat = 108
    private static let gap: CGFloat = 6

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Self.gap) {
                    if let comic = reader.comic {
                        ForEach(0..<max(reader.pageCount, 0), id: \.self) { index in
                            thumb(comic: comic, index: index)
                                .id(index)
                        }
                    }
                }
                .padding(.horizontal, 14)
            }
            .frame(height: Self.thumbHeight + 8)
            .onAppear {
                proxy.scrollTo(reader.page, anchor: .center)
            }
            .onChange(of: reader.page) { newPage in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(newPage, anchor: .center)
                }
            }
        }
    }

    private func thumb(comic: Comic, index: Int) -> some View {
        Button {
            reader.setPage(index)
        } label: {
            ZStack(alignment: .bottom) {
                ThumbImage(comic: comic, index: index)
                    .frame(width: Self.thumbWidth, height: Self.thumbHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                Text("\(index + 1)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(.bottom, 3)
            }
            .overlay {
                if index == reader.page {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if reader.bookmarks.contains(index) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// 单张缩略图（异步从 PageProvider 取 180px JPEG）
private struct ThumbImage: View {
    let comic: Comic
    let index: Int

    @EnvironmentObject private var pages: PageProvider
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemFill)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .task(id: "\(comic.id)-\(index)") {
            image = await pages.thumbnail(comic: comic, index: index)
        }
    }
}
