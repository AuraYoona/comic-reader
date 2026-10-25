import Foundation

// MARK: - 局域网传输的一次性密码
//
// 每次启动服务生成一个新的 6 位数字，写在地址路径里（二维码直接带上）。
// 6 位数字便于手输；服务端另有失败次数上限，触发后自动停服，避免被穷举。
// 比较使用常量时间实现，长度固定且公开，不做长度隐藏。

public enum TransferToken {
    public static let length = 6

    /// 生成 6 位数字密码（前导零保留）；可注入随机源便于测试
    public static func generate<R: RandomNumberGenerator>(using rng: inout R) -> String {
        let value = Int.random(in: 0..<1_000_000, using: &rng)
        let raw = String(value)
        let padding = Swift.max(0, length - raw.count)
        return String(repeating: "0", count: padding) + raw
    }

    public static func generate() -> String {
        var rng = SystemRandomNumberGenerator()
        return generate(using: &rng)
    }

    /// 是否为合法的 6 位数字
    public static func isWellFormed(_ token: String) -> Bool {
        guard token.count == length else { return false }
        return token.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
    }

    /// 常量时间比较（长度不同提前返回；长度固定为 6 位，不构成信息泄露）
    public static func matches(_ candidate: String, expected: String) -> Bool {
        let a = Array(candidate.utf8)
        let b = Array(expected.utf8)
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for index in 0..<a.count {
            diff |= a[index] ^ b[index]
        }
        return diff == 0
    }
}
