import SwiftUI
import UniformTypeIdentifiers
import ComicReaderCore

// MARK: - 设置（SettingsModal.tsx 的移植；桌面专属项按计划隐藏、键保留以兼容备份）
//
// 隐藏项：自动检查更新（桌面 electron-updater）、鼠标侧键翻页。
// 「打开所在位置」类功能不存在；库目录区改为「文件」App 的沙盒 Comics 目录。

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var shelf: ShelfStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var shareURL: URL?
    @State private var restoreMode: RestoreMode?
    @State private var pendingReplaceURL: URL?
    @State private var showReplaceConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                readingSection
                startupSection
                librarySection
                backupSection
                extensionsSection
                aboutSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .fileImporter(
            isPresented: Binding(
                get: { restoreMode != nil && pendingReplaceURL == nil },
                set: { if !$0 { restoreMode = nil } }
            ),
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleRestorePick(result)
        }
        .sheet(item: Binding(
            get: { shareURL.map(ShareItem.init) },
            set: { if $0 == nil { shareURL = nil } }
        )) { item in
            ActivityView(items: [item.url])
        }
        .alert("覆盖恢复？", isPresented: $showReplaceConfirm) {
            Button("取消", role: .cancel) { pendingReplaceURL = nil }
            Button("恢复", role: .destructive) {
                if let url = pendingReplaceURL {
                    _ = shelf.restoreBackup(from: url, mode: .replace)
                }
                pendingReplaceURL = nil
            }
        } message: {
            Text("当前书架将被备份内容替换（恢复前会自动备份当前数据到 .pre-restore 文件）。")
        }
    }

    // MARK: 外观

    private var appearanceSection: some View {
        Section("外观") {
            Picker("主题", selection: themeBinding) {
                Text("浅色").tag(ThemeMode.light)
                Text("深色").tag(ThemeMode.dark)
                Text("跟随系统").tag(ThemeMode.system)
            }
            .pickerStyle(.segmented)

            Picker("卡片大小", selection: cardSizeBinding) {
                Text("小").tag(CardSize.small)
                Text("中").tag(CardSize.medium)
                Text("大").tag(CardSize.large)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: 阅读

    private var readingSection: some View {
        Section("阅读") {
            Picker("默认方向", selection: directionBinding) {
                Text("从左到右").tag(ReadingDirection.ltr)
                Text("从右到左").tag(ReadingDirection.rtl)
            }
            .pickerStyle(.segmented)

            Picker("默认模式", selection: modeBinding) {
                Text("单页").tag(ReadingMode.single)
                Text("双页").tag(ReadingMode.double)
                Text("连续滚动").tag(ReadingMode.scroll)
            }
            .pickerStyle(.segmented)

            Picker("默认缩放", selection: zoomBinding) {
                Text("适应宽度").tag(ZoomMode.fitWidth)
                Text("适应高度").tag(ZoomMode.fitHeight)
                Text("原始大小").tag(ZoomMode.original)
            }
            .pickerStyle(.segmented)

            Toggle("封面单独占屏", isOn: boolBinding(\.doubleCoverSingle))
            Toggle("跨页图铺满整屏", isOn: boolBinding(\.widePageSpread))
            Toggle("默认自动裁掉扫描白边", isOn: boolBinding(\.autoCrop))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("阅读亮度")
                    Spacer()
                    Text("\(Int((settings.settings.brightness * 100).rounded()))%")
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { settings.settings.brightness },
                        set: { settings.update { s in s.brightness = $0 } }
                    ),
                    in: BrightnessLimits.min...BrightnessLimits.max,
                    step: 0.05
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("自动翻页间隔")
                    Spacer()
                    Text("\(settings.settings.autoTurnSeconds) 秒")
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(settings.settings.autoTurnSeconds) },
                        set: { settings.setAutoTurnSeconds(Int($0)) }
                    ),
                    in: Double(AutoTurnLimits.min)...Double(AutoTurnLimits.max),
                    step: 1
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("条漫平滑滚动速度")
                    Spacer()
                    Text("\(Int(settings.settings.autoScrollSpeed)) px/s")
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { settings.settings.autoScrollSpeed },
                        set: { settings.setAutoScrollSpeed($0) }
                    ),
                    in: AutoScrollLimits.min...AutoScrollLimits.max,
                    step: AutoScrollLimits.step
                )
            }
        }
    }

    // MARK: 启动

    private var startupSection: some View {
        Section("启动") {
            Toggle("启动时打开上次阅读的漫画", isOn: boolBinding(\.openLastOnStartup))
        }
    }

    // MARK: 漫画库目录

    private var librarySection: some View {
        Section {
            Toggle("启动时扫描库目录", isOn: boolBinding(\.autoScanRoots))

            ForEach(settings.settings.libraryRoots, id: \.self) { root in
                HStack {
                    Text(displayPath(root))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        settings.update { $0.libraryRoots.removeAll { $0 == root } }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("立即扫描") {
                Task { await shelf.scanRoots() }
            }
            .disabled(shelf.importing.active)
        } header: {
            Text("漫画库目录")
        } footer: {
            Text("把漫画（文件夹 / ZIP / CBZ / RAR / CBR / PDF）放进「文件」App 里 ComicReader 的 Comics 目录，扫描后会自动上架。也可以随时用书架顶栏的「导入」复制进来。")
        }
    }

    /// 沙盒路径太长，显示为「…/Comics/子目录」的可读形式
    private func displayPath(_ path: String) -> String {
        if let range = path.range(of: "/Documents/Comics/") {
            return "Comics/" + path[range.upperBound...]
        }
        if path.hasSuffix("/Documents/Comics") {
            return "Comics"
        }
        return (path as NSString).lastPathComponent
    }

    // MARK: 数据备份

    private var backupSection: some View {
        Section {
            Button("导出备份…") {
                if let url = shelf.exportBackup() {
                    shareURL = url
                }
            }

            Button("从备份合并…") {
                restoreMode = .merge
                pendingReplaceURL = nil
            }

            Button("覆盖恢复…", role: .destructive) {
                restoreMode = .replace
                pendingReplaceURL = nil
            }
        } header: {
            Text("数据备份")
        } footer: {
            Text("备份包含书架、分类、类型标签、进度、书签与封面，与桌面版格式互通；导出后用「文件」App 存走，以后可以合并导入或覆盖恢复。")
        }
    }

    // MARK: 扩展功能

    private var extensionsSection: some View {
        Section {
            Toggle("自定义分类", isOn: extensionBinding(\.categories))
            Toggle("书签", isOn: extensionBinding(\.bookmarks))
        } header: {
            Text("扩展功能")
        } footer: {
            Text("关闭只隐藏入口，已有数据不会删除。")
        }
    }

    // MARK: 关于

    private var aboutSection: some View {
        Section("关于") {
            HStack {
                Text("版本")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.7.0"
        return "v\(v)（iOS）"
    }

    // MARK: 绑定与动作

    private var themeBinding: Binding<ThemeMode> {
        Binding(
            get: { settings.settings.theme },
            set: { v in settings.update { $0.theme = v } }
        )
    }

    private var cardSizeBinding: Binding<CardSize> {
        Binding(
            get: { settings.settings.cardSize },
            set: { v in settings.update { $0.cardSize = v } }
        )
    }

    private var directionBinding: Binding<ReadingDirection> {
        Binding(
            get: { settings.settings.readingDirection },
            set: { v in settings.update { $0.readingDirection = v } }
        )
    }

    private var modeBinding: Binding<ReadingMode> {
        Binding(
            get: { settings.settings.defaultMode },
            set: { v in settings.update { $0.defaultMode = v } }
        )
    }

    private var zoomBinding: Binding<ZoomMode> {
        Binding(
            get: { settings.settings.defaultZoom },
            set: { v in settings.update { $0.defaultZoom = v } }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings.settings[keyPath: keyPath] },
            set: { v in settings.update { $0[keyPath: keyPath] = v } }
        )
    }

    private func extensionBinding(_ keyPath: WritableKeyPath<ExtensionFlags, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings.settings.extensions[keyPath: keyPath] },
            set: { v in settings.update { $0.extensions[keyPath: keyPath] = v } }
        )
    }

    private func handleRestorePick(_ result: Result<[URL], Error>) {
        defer {
            restoreMode = nil
        }
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard let mode = restoreMode else { return }
        switch mode {
        case .merge:
            _ = shelf.restoreBackup(from: url, mode: .merge)
        case .replace:
            pendingReplaceURL = url
            showReplaceConfirm = true
        }
    }
}

// MARK: - 分享面板（导出备份用）

struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
