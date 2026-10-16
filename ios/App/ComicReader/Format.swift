import Foundation
import ComicReaderCore

// MARK: - 展示用格式化（src/renderer/src/utils/format.ts 的移植）

enum Format {
    /// 相对时间：刚刚 / N 分钟前 / N 小时前 / N 天前（<30 天）/ YYYY-MM-DD
    static func relativeTime(_ ts: Double?, now: Double = Date().timeIntervalSince1970 * 1000) -> String {
        guard let ts else { return "未读" }
        let minute = 60_000.0
        let hour = 60 * minute
        let day = 24 * hour
        let diff = now - ts
        if diff < minute { return "刚刚" }
        if diff < hour { return "\(Int(diff / minute)) 分钟前" }
        if diff < day { return "\(Int(diff / hour)) 小时前" }
        if diff < 30 * day { return "\(Int(diff / day)) 天前" }
        let date = Date(timeIntervalSince1970: ts / 1000)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    /// 阅读百分比（0–100 的整数）。未读返回 0。
    static func readPercent(_ comic: Comic) -> Int {
        guard comic.lastReadAt != nil, comic.pageCount > 0 else { return 0 }
        return min(100, Int((Double(comic.lastReadPage + 1) / Double(comic.pageCount) * 100).rounded()))
    }

    static func basename(_ path: String) -> String {
        path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? path
    }
}
