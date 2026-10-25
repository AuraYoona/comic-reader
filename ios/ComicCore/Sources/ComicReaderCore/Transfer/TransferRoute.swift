import Foundation

// MARK: - 局域网传输路由
//
// 无密码设计：同一 Wi-Fi 网段本身就是信任边界（路由器隔离了外部访问），
// 再套一层 6 位数字口令只增加输入摩擦。页面以 / 结尾提供，所有接口
// 都用相对路径。
//
// 纯字符串处理，便于单测（含百分号解码、尾斜杠与未知路径）。

public enum TransferRoute: Equatable, Sendable {
    /// GET / —— 传输主页面
    case landing
    /// PUT/POST /upload?name=… —— 裸 body 上传
    case upload(fileName: String?)
    /// GET /state —— 最近上传状态
    case state
    /// GET /library —— 书架列表
    case library
    /// GET /cover/<id> —— 封面
    case cover(id: String)
    /// GET /download/<id> —— 下载原文件 / 文件夹打 zip
    case download(id: String)
    /// 未知路径
    case notFound

    /// 解析请求目标（origin-form：以 "/" 开头的 path + 可选 query）
    public static func parse(_ target: String) -> TransferRoute {
        var raw = target
        if let hash = raw.firstIndex(of: "#") {
            raw = String(raw[..<hash])
        }

        var path = raw
        var query: String?
        if let mark = raw.firstIndex(of: "?") {
            path = String(raw[..<mark])
            query = String(raw[raw.index(after: mark)...])
        }

        guard path.hasPrefix("/") else { return .notFound }
        let rawSegments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !rawSegments.isEmpty else { return .landing }

        var segments: [String] = []
        segments.reserveCapacity(rawSegments.count)
        for rawSegment in rawSegments {
            guard let decoded = rawSegment.removingPercentEncoding, !decoded.isEmpty else {
                return .notFound
            }
            segments.append(decoded)
        }

        switch segments[0] {
        case "upload":
            guard segments.count == 1 else { return .notFound }
            let name = query.flatMap { queryValue($0, key: "name") }
            return .upload(fileName: name)
        case "state":
            guard segments.count == 1 else { return .notFound }
            return .state
        case "library":
            guard segments.count == 1 else { return .notFound }
            return .library
        case "cover":
            guard segments.count == 2 else { return .notFound }
            return .cover(id: segments[1])
        case "download":
            guard segments.count == 2 else { return .notFound }
            return .download(id: segments[1])
        default:
            return .notFound
        }
    }

    // MARK: query

    /// 取 query 中某个参数；沿用 application/x-www-form-urlencoded 的
    /// 「+ = 空格、%XX = 字节」规则。同名参数以后出现的为准。
    public static func queryValue(_ query: String, key: String) -> String? {
        var result: String?
        for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
            guard let equals = pair.firstIndex(of: "=") else { continue }
            let rawKey = String(pair[..<equals])
            let rawValue = String(pair[pair.index(after: equals)...])
            guard let decodedKey = percentDecode(rawKey), decodedKey == key else { continue }
            guard let decodedValue = percentDecode(rawValue) else { return nil }
            result = decodedValue
        }
        return result
    }

    private static func percentDecode(_ value: String) -> String? {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
    }
}
