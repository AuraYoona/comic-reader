import Foundation

// MARK: - HTTP 响应头序列化（局域网传输）
//
// 服务端自己拼响应，只有很少几种状态码；集中在这里便于单测，
// 也顺手挡住 CRLF 注入（header 值里出现换行会被剔除）。

public enum HTTPStatus: Int, Sendable {
    case ok = 200
    case noContent = 204
    case movedPermanently = 301
    case badRequest = 400
    case forbidden = 403
    case notFound = 404
    case methodNotAllowed = 405
    case lengthRequired = 411
    case payloadTooLarge = 413
    case internalServerError = 500
    case notImplemented = 501
    case serviceUnavailable = 503
    case insufficientStorage = 507

    public var reason: String {
        switch self {
        case .ok: return "OK"
        case .noContent: return "No Content"
        case .movedPermanently: return "Moved Permanently"
        case .badRequest: return "Bad Request"
        case .forbidden: return "Forbidden"
        case .notFound: return "Not Found"
        case .methodNotAllowed: return "Method Not Allowed"
        case .lengthRequired: return "Length Required"
        case .payloadTooLarge: return "Payload Too Large"
        case .internalServerError: return "Internal Server Error"
        case .notImplemented: return "Not Implemented"
        case .serviceUnavailable: return "Service Unavailable"
        case .insufficientStorage: return "Insufficient Storage"
        }
    }
}

public enum HTTPResponseHead {
    /// 上传前对 Expect: 100-continue 的临时响应
    public static let continueResponse = Data("HTTP/1.1 100 Continue\r\n\r\n".utf8)

    /// 生成完整响应头（含结尾空行）；body 由调用方拼在后面
    public static func serialize(
        status: HTTPStatus,
        headers: [(String, String)] = [],
        contentLength: Int? = nil
    ) -> Data {
        var lines: [String] = []
        lines.reserveCapacity(headers.count + 3)
        lines.append("HTTP/1.1 \(status.rawValue) \(status.reason)")

        var hasContentLength = false
        for (name, value) in headers {
            // header 名与值都不能包含 CR/LF，否则可注入额外的响应头
            let cleanName = name.filter { $0 != "\r" && $0 != "\n" && $0 != ":" }
            guard !cleanName.isEmpty else { continue }
            if cleanName.lowercased() == "content-length" { hasContentLength = true }
            let cleanValue = value.filter { $0 != "\r" && $0 != "\n" }
            lines.append("\(cleanName): \(cleanValue)")
        }

        if let contentLength, !hasContentLength {
            lines.append("Content-Length: \(contentLength)")
        }

        // 两个空串 + 换行连接 = 头部结束的空行
        lines.append("")
        lines.append("")
        return Data(lines.joined(separator: "\r\n").utf8)
    }
}
