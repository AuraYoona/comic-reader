import Foundation

// MARK: - 局域网传输路由
//
// 密码就是路径的第一段：http://<ip>:<port>/<6 位密码>/…
// 页面用相对路径访问 upload / state / library / cover / download，
// 因此页面本身不需要在 JS 里拼密码。
//
// 纯字符串处理，便于单测（含百分号解码、尾斜杠与未知路径）。

public enum TransferRoute: Equatable, Sendable {
    /// GET / —— 密码输入页（无鉴权）
    case landing
    /// GET /<code>/ —— 传输主页面
    case page(token: String, trailingSlash: Bool)
    /// PUT/POST /<code>/upload?name=… —— 裸 body 上传
    case upload(token: String, fileName: String?)
    /// GET /<code>/state —— 最近上传状态
    case state(token: String)
    /// GET /<code>/library —— 书架列表
    case library(token: String)
    /// GET /<code>/cover/<id> —— 封面
    case cover(token: String, id: String)
    /// GET /<code>/download/<id> —— 下载原文件 / 文件夹打 zip
    case download(token: String, id: String)
    /// 未知路径；尽量保留第一段密码，便于区分「404」与「密码错误」
    case notFound(token: String?)

    /// 路由里的密码（landing 为 nil）
    public var token: String? {
        switch self {
        case .landing:
            return nil
        case .page(let token, _),
             .upload(let token, _),
             .state(let token),
             .library(let token),
             .cover(let token, _),
             .download(let token, _):
            return token
        case .notFound(let token):
            return token
        }
    }

    /// 该路由是否必须携带正确密码
    public var requiresToken: Bool {
        switch self {
        case .landing:
            return false
        default:
            return true
        }
    }

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

        guard path.hasPrefix("/") else { return .notFound(token: nil) }

        let trailingSlash = path.count > 1 && path.hasSuffix("/")
        let rawSegments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !rawSegments.isEmpty else { return .landing }

        var segments: [String] = []
        segments.reserveCapacity(rawSegments.count)
        for rawSegment in rawSegments {
            guard let decoded = rawSegment.removingPercentEncoding, !decoded.isEmpty else {
                return .notFound(token: nil)
            }
            segments.append(decoded)
        }

        let token = segments[0]
        guard token.count <= 64 else { return .notFound(token: nil) }

        if segments.count == 1 {
            return .page(token: token, trailingSlash: trailingSlash)
        }

        switch segments[1] {
        case "upload":
            guard segments.count == 2 else { return .notFound(token: token) }
            let name = query.flatMap { queryValue($0, key: "name") }
            return .upload(token: token, fileName: name)
        case "state":
            guard segments.count == 2 else { return .notFound(token: token) }
            return .state(token: token)
        case "library":
            guard segments.count == 2 else { return .notFound(token: token) }
            return .library(token: token)
        case "cover":
            guard segments.count == 3 else { return .notFound(token: token) }
            return .cover(token: token, id: segments[2])
        case "download":
            guard segments.count == 3 else { return .notFound(token: token) }
            return .download(token: token, id: segments[2])
        default:
            return .notFound(token: token)
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
