import Foundation
import SwiftUI
import ComicReaderCore

// MARK: - 全局设置状态（src/renderer/src/store/settings.ts 的移植）

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: AppSettings = .defaults

    private let db: LibraryDatabase

    init(db: LibraryDatabase) {
        self.db = db
    }

    func load() {
        settings = db.getSettings()
    }

    /// 乐观更新 + 以数据库净化后的结果为准（对齐 settings.ts 的 update）
    func update(_ mutate: (inout AppSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        settings = db.saveSettings { $0 = copy }
    }

    /// 自动翻页间隔（秒）：夹界 + 无变化不写
    func setAutoTurnSeconds(_ value: Int) {
        let clamped = AutoTurnLimits.clamp(value)
        guard clamped != settings.autoTurnSeconds else { return }
        update { $0.autoTurnSeconds = clamped }
    }

    func adjustAutoTurn(by delta: Int) {
        setAutoTurnSeconds(settings.autoTurnSeconds + delta)
    }

    /// 条漫平滑滚动速度（px/s）：夹界 + 无变化不写
    func setAutoScrollSpeed(_ value: Double) {
        let clamped = AutoScrollLimits.clamp(value)
        guard clamped != settings.autoScrollSpeed else { return }
        update { $0.autoScrollSpeed = clamped }
    }

    func adjustAutoScrollSpeed(by delta: Double) {
        setAutoScrollSpeed(settings.autoScrollSpeed + delta)
    }

    /// 主题 → SwiftUI 配色方案（system 返回 nil = 跟随系统）
    var preferredScheme: ColorScheme? {
        switch settings.theme {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    // 便捷只读

    var extensions: ExtensionFlags { settings.extensions }
    var cardSize: CardSize { settings.cardSize }
}
