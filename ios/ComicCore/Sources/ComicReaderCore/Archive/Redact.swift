import Foundation

// MARK: - 日志脱敏（src/main/utils/redact.ts 的移植）
//
// 排障日志会被贴到 issue 里，而漫画标题和来源路径本身就是隐私。
// 这里的原则是「保留形状，去掉内容」：
//   - 漫画只写 id 前 8 位，不写标题
//   - 路径只保留盘符 / 根、目录层数与扩展名

/// 日志里代指一本漫画
public func comicRef(_ id: String) -> String {
    "#\(id.prefix(8))"
}

/**
 路径脱敏。
   D:/comics/作者A/第01卷.cbz  →  D:\…2层\*.cbz
   //NAS/share/a/b             →  \\…3层\*
   /var/mobile/…/x/y           →  /…3层\*
 */
public func redactPath(_ p: String) -> String {
    if p.isEmpty { return "(空路径)" }
    let sep = "\\"
    // UNC 要在归一化之前判断：下面的压缩会把连续分隔符压成一个
    let isUnc = p.hasPrefix("\\\\") || p.hasPrefix("//")
    let slashed = p
        .replacingOccurrences(of: "\\", with: "/")
        .replacingOccurrences(of: "//+", with: "/", options: .regularExpression)

    var prefix = ""
    var rest = slashed
    if isUnc {
        prefix = "\\\\"
        rest = String(rest.drop(while: { $0 == "/" }))
    } else if slashed.count >= 3,
              slashed[slashed.startIndex].isLetter,
              slashed[slashed.index(slashed.startIndex, offsetBy: 1)] == ":",
              slashed[slashed.index(slashed.startIndex, offsetBy: 2)] == "/" {
        prefix = "\(slashed.prefix(2))\\"
        rest = String(slashed.dropFirst(3))
    } else if slashed.count == 2, slashed.last == ":" {
        return "\(slashed)\\*"
    } else if slashed.hasPrefix("/") {
        prefix = "/"
        rest = String(slashed.dropFirst())
    }

    var segments = rest.split(separator: "/").map(String.init)
    let leaf = segments.popLast() ?? ""
    let ext: String
    if let dot = leaf.lastIndex(of: "."), dot != leaf.startIndex {
        ext = String(leaf[dot...]).lowercased()
    } else {
        ext = ""
    }
    let middle = segments.count > 0 ? "…\(segments.count)层\\": ""
    return "\(prefix)\(middle)*\(ext)"
}
