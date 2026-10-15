import Foundation

// MARK: - 阅读模式

/// 阅读模式：single 单页 / double 双页 / scroll 连续滚动
public enum ReadingMode: String, Codable, CaseIterable, Sendable {
    case single
    case double
    case scroll
}

/// 缩放模式：fitWidth 适应宽度 / fitHeight 适应高度 / original 原始大小
public enum ZoomMode: String, Codable, CaseIterable, Sendable {
    case fitWidth
    case fitHeight
    case original
}

/// 阅读方向：ltr 从左到右 / rtl 从右到左
public enum ReadingDirection: String, Codable, CaseIterable, Sendable {
    case ltr
    case rtl
}

/// 主题：light 浅色 / dark 深色 / system 跟随系统
public enum ThemeMode: String, Codable, CaseIterable, Sendable {
    case light
    case dark
    case system
}

/// 书架排序：title 名称 / lastReadAt 最近阅读 / addedAt 导入时间
public enum SortKey: String, Codable, CaseIterable, Sendable {
    case title
    case lastReadAt
    case addedAt
}

/// 卡片大小：small / medium / large
public enum CardSize: String, Codable, CaseIterable, Sendable {
    case small
    case medium
    case large
}

/// 可选扩展功能：categories 自定义分类 / bookmarks 书签
public enum ExtensionId: String, Codable, CaseIterable, Sendable {
    case categories
    case bookmarks

    public static let all: Set<String> = ["categories", "bookmarks"]
}

/// 来源类型：folder 本地文件夹 / archive 压缩包
public enum SourceType: String, Codable, CaseIterable, Sendable {
    case folder
    case archive
}

/// 类型标签：manga 日漫 / manhwa 韩漫 / manhua 国漫 / western 美漫
public enum ComicStyle: String, Codable, CaseIterable, Sendable {
    case manga
    case manhwa
    case manhua
    case western

    public static let all: Set<String> = ["manga", "manhwa", "manhua", "western"]
}

/// 恢复模式：merge 合并导入 / replace 覆盖恢复
public enum RestoreMode: String, Codable, CaseIterable, Sendable {
    case merge
    case replace
}

// MARK: - 数值范围（与桌面版 shared/types.ts 完全一致）

public enum ZoomLimits {
    public static let scaleMin: Double = 0.25
    public static let scaleMax: Double = 4

    /// 缩放倍率 clamp 到 [0.25, 4]，保留两位小数
    public static func clampScale(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        let clamped = min(max(value, scaleMin), scaleMax)
        return (clamped * 100).rounded() / 100
    }
}

public enum BrightnessLimits {
    public static let min: Double = 0.3
    public static let max: Double = 1.2
    public static let defaultValue: Double = 1

    /// 亮度 clamp 到 [0.3, 1.2]，按 0.05 步进取整
    public static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return Self.defaultValue }
        let clamped = min(max(value, min), max)
        return (clamped * 20).rounded() / 20
    }
}

public enum AutoTurnLimits {
    public static let min: Int = 2
    public static let max: Int = 60
    public static let defaultSeconds: Int = 6

    /// 自动翻页间隔 clamp 到 [2, 60] 秒（整数）
    public static func clamp(_ value: Int) -> Int {
        min(max(value, min), max)
    }
}

public enum AutoScrollLimits {
    public static let min: Double = 10
    public static let max: Double = 400
    public static let step: Double = 10
    public static let defaultSpeed: Double = 80

    /// 平滑滚动速度 clamp 到 [10, 400] px/s，按 10 取整
    public static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return Self.defaultSpeed }
        let clamped = min(max(value, min), max)
        return (clamped / step).rounded() * step
    }
}

// MARK: - 尺寸限制

public enum Limits {
    /// 分类名最长 20 字符
    public static let categoryNameMax = 20
    /// 书架标题最长 120 字符
    public static let titleMax = 120
    /// 库根目录最多 20 个
    public static let libraryRootsMax = 20
    /// 分类调色板（8 色循环取用）
    public static let categoryColors: [String] = [
        "#ef4444", "#f97316", "#eab308", "#22c55e",
        "#14b8a6", "#3b82f6", "#8b5cf6", "#ec4899"
    ]
}

// MARK: - 类型标签预设（打标签时写入该漫画的阅读偏好）

/// 某类型标签对应的阅读预设；返回 nil 表示该标签没有预设要写
public func comicStylePreset(_ style: ComicStyle) -> ComicReaderPrefs {
    switch style {
    case .manga:
        // 日漫：从右到左，封面单独占屏
        return ComicReaderPrefs(
            mode: .single, direction: .rtl, pageOffset: 1, autoScroll: false
        )
    case .manhwa, .manhua:
        // 韩漫 / 国漫：条漫连续滚动，自动翻页改为平滑向下滚动
        return ComicReaderPrefs(
            mode: .scroll, direction: .ltr, pageOffset: 1, autoScroll: true
        )
    case .western:
        // 美漫：从左到右，封面单独占屏
        return ComicReaderPrefs(
            mode: .single, direction: .ltr, pageOffset: 1, autoScroll: false
        )
    }
}

public enum ComicStyleInfo {
    /// 界面显示名
    public static func label(_ style: ComicStyle) -> String {
        switch style {
        case .manga: return "日漫"
        case .manhwa: return "韩漫"
        case .manhua: return "国漫"
        case .western: return "美漫"
        }
    }

    /// 悬浮提示
    public static func hint(_ style: ComicStyle) -> String {
        switch style {
        case .manga: return "从右到左翻页，封面单独占屏"
        case .manhwa: return "条漫：连续滚动，自动翻页改为平滑向下滚动"
        case .manhua: return "条漫：连续滚动，自动翻页改为平滑向下滚动"
        case .western: return "从左到右翻页，封面单独占屏"
        }
    }
}
