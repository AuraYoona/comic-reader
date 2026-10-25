import SwiftUI

// MARK: - App 入口
//
// 启动与生命周期都交给 AppModel（对齐桌面版 App.tsx 的 boot 顺序与 before-quit 的落盘）。

@main
struct ComicReaderApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.shelf)
                .environmentObject(model.reader)
                .environmentObject(model.settings)
                .environmentObject(model.toasts)
                .environmentObject(model.pages)
                .environmentObject(model.covers)
                .environmentObject(model.transfer)
                // 明暗主题的 preferredColorScheme 在 RootView 上（它观察
                // SettingsStore）：App 结构体只观察 model，嵌套在
                // model.settings 里的变更不会传播到这里，切换不会立即生效
                .task { await model.boot() }
                .onChange(of: scenePhase) { phase in
                    model.handleScenePhase(phase)
                }
                .onOpenURL { url in
                    // 「文件」App 里用本应用打开压缩包 / PDF：复制进沙盒后导入
                    Task { await model.importFlow.importIncoming(url: url) }
                }
        }
    }
}
