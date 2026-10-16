import Foundation

// MARK: - 自然排序（src/main/utils/naturalSort.ts 的移植）
//
// 桌面版用 Intl.Collator(['zh','en'], { numeric: true, sensitivity: 'base' })：
//   - 数字段按数值比较（"2" < "10"）
//   - 忽大小写与变音符号（sensitivity: 'base'）
//   - zh 优先的排序规则
// iOS 上不用 localizedStandardCompare（跟随设备语言，页序会随系统语言漂移），
// 而是固定 zh locale + .numeric + 三个 insensitivity，保证与桌面版一致的确定性。
//
// 稳定性：V8 的 sort 是稳定排序（相等元素保持原顺序）；Swift 的 sorted 不保证稳定，
// 所以 naturalSort 排 (index, name) 二元组，比较相等时回退到原始下标。

/// 返回 -1 / 0 / 1
public func naturalCompare(_ a: String, _ b: String) -> Int {
    let nsA = a as NSString
    let result = nsA.compare(
        b,
        options: [.numeric, .caseInsensitive, .diacriticInsensitive, .widthInsensitive],
        range: NSRange(location: 0, length: nsA.length),
        locale: Locale(identifier: "zh")
    )
    switch result {
    case .orderedAscending: return -1
    case .orderedSame: return 0
    case .orderedDescending: return 1
    }
}

/// 自然排序；相等元素保持原顺序（稳定）
public func naturalSort(_ items: [String]) -> [String] {
    let indexed = items.enumerated().map { (index: $0.offset, name: $0.element) }
    let sorted = indexed.sorted { lhs, rhs in
        let c = naturalCompare(lhs.name, rhs.name)
        return c < 0 || (c == 0 && lhs.index < rhs.index)
    }
    return sorted.map(\.name)
}
