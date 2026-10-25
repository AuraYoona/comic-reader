import Foundation

// MARK: - HTTP/1.1 请求头解析（局域网传输）
//
// 只解析 head（请求行 + headers），body 由调用方按 framing 决定如何消费：
// 上传时直接流式落盘，其余请求读完 head 就响应并关闭连接。
// 纯 Foundation，无平台依赖 —— Windows 本地类型检查与 macOS CI 单测都能覆盖。
//
// 容错策略：接受 CRLF 与裸 LF；header 名大小写不敏感；同名 header 合并
// （Content-Length 必须一致）；Transfer-Encoding 与 Content-Length 同时出现
// 视为请求走私风险，直接拒绝。

/// 解析相关的硬上限
public enum HTTPLimits {
    /// 请求头总长（不含结尾空行）
    public static let maxHeadBytes = 16 * 1024
    /// Content-Length 上限（1 TiB；实际还会被磁盘空间检查拦住）
    public static let maxContentLength = 1_099_511_627_776
    /// 单个 chunk 上限（1 GiB）
    public static let maxChunkBytes = 1_073_741_824
    /// chunk size 行 / trailer 行长度上限
    public static let maxChunkLineBytes = 8 * 1024
}

/// 请求体的分帧方式
public enum HTTPBodyFraming: Equatable, Sendable {
    /// 没有请求体（没有 Content-Length，也没有 Transfer-Encoding）
    case none
    /// 固定长度（Content-Length）
    case contentLength(Int)
    /// 分块传输（Transfer-Encoding: chunked）
    case chunked
}

/// 请求头解析失败原因（对应 400 / 411 / 501 等响应）
public enum HTTPHeadError: Error, Equatable, Sendable {
    case headTooLarge
    case malformedRequestLine
    case unsupportedVersion
    case malformedHeader
    case invalidContentLength
    case conflictingContentLength
    case ambiguousBodyFraming
    case unsupportedTransferEncoding
}

/// 解析完成的请求头
public struct HTTPRequestHead: Equatable, Sendable {
    public var method: String
    public var target: String
    public var version: String
    /// header 名统一小写；同名值以 ", " 合并
    public var headers: [String: String]
    public var framing: HTTPBodyFraming
    public var expectsContinue: Bool

    public init(
        method: String,
        target: String,
        version: String = "HTTP/1.1",
        headers: [String: String] = [:],
        framing: HTTPBodyFraming = .none,
        expectsContinue: Bool = false
    ) {
        self.method = method
        self.target = target
        self.version = version
        self.headers = headers
        self.framing = framing
        self.expectsContinue = expectsContinue
    }

    /// 大小写不敏感地取 header
    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    public var isHeadRequest: Bool { method == "HEAD" }
}

/// 增量解析结果
public enum HTTPHeadParseResult: Equatable, Sendable {
    /// 还没读到完整的 head
    case incomplete
    /// 解析成功；consumed 是 head 结束（含空行）后的字节数
    case complete(HTTPRequestHead, consumed: Int)
    case failure(HTTPHeadError)
}

public enum HTTPRequestHeadParser {
    private static let crlfcrlf = Data([13, 10, 13, 10])
    private static let lflf = Data([10, 10])

    /// 从缓冲区尝试解析一个请求头；调用方按 consumed 丢掉已消费字节
    public static func parse(_ data: Data) -> HTTPHeadParseResult {
        // 同时找 CRLFCRLF 与 LFLF，取更早出现的那个。
        // 只优先 CRLF 会把「LF 换行 + 二进制 body 里恰好有 CRLFCRLF」误判成请求头结束。
        let crlfRange = data.range(of: crlfcrlf)
        let lfRange = data.range(of: lflf)
        let terminator: (start: Int, end: Int)
        switch (crlfRange, lfRange) {
        case (let crlf?, let lf?):
            terminator = crlf.lowerBound <= lf.lowerBound
                ? (crlf.lowerBound, crlf.upperBound)
                : (lf.lowerBound, lf.upperBound)
        case (let crlf?, nil):
            terminator = (crlf.lowerBound, crlf.upperBound)
        case (nil, let lf?):
            terminator = (lf.lowerBound, lf.upperBound)
        case (nil, nil):
            return data.count > HTTPLimits.maxHeadBytes
                ? .failure(.headTooLarge)
                : .incomplete
        }

        guard terminator.start <= HTTPLimits.maxHeadBytes else {
            return .failure(.headTooLarge)
        }

        let headData = data[data.startIndex..<terminator.start]
        let headText = String(decoding: headData, as: UTF8.self)
        var lines = headText.components(separatedBy: "\n").map { line -> String in
            line.hasSuffix("\r") ? String(line.dropLast()) : line
        }
        // 结尾空行（分隔符的一部分）不属于 head
        while let last = lines.last, last.isEmpty {
            lines.removeLast()
        }

        guard let requestLine = lines.first, !requestLine.isEmpty else {
            return .failure(.malformedRequestLine)
        }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 3 else {
            return .failure(.malformedRequestLine)
        }
        let method = parts[0]
        let target = parts[1]
        let version = parts[2]
        guard isToken(method), isValidTarget(target) else {
            return .failure(.malformedRequestLine)
        }
        guard version == "HTTP/1.1" || version == "HTTP/1.0" else {
            return .failure(.unsupportedVersion)
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { continue }
            guard let colon = line.firstIndex(of: ":") else {
                return .failure(.malformedHeader)
            }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard isToken(name) else {
                return .failure(.malformedHeader)
            }
            if let existing = headers[name] {
                // Content-Length 重复且不一致是典型的请求走私手法
                if name == "content-length" {
                    guard existing == value else {
                        return .failure(.conflictingContentLength)
                    }
                } else {
                    headers[name] = existing + ", " + value
                }
            } else {
                headers[name] = value
            }
        }

        let framing: HTTPBodyFraming
        if let transferEncoding = headers["transfer-encoding"] {
            // TE 与 CL 并存时不同实现取值不同，直接拒绝
            guard headers["content-length"] == nil else {
                return .failure(.ambiguousBodyFraming)
            }
            let codings = transferEncoding
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            guard let last = codings.last, last == "chunked" else {
                return .failure(.unsupportedTransferEncoding)
            }
            guard codings.dropLast().allSatisfy({ $0 == "identity" }) else {
                return .failure(.unsupportedTransferEncoding)
            }
            framing = .chunked
        } else if let raw = headers["content-length"] {
            guard !raw.isEmpty,
                  raw.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                  let length = Int(raw),
                  length >= 0,
                  length <= HTTPLimits.maxContentLength else {
                return .failure(.invalidContentLength)
            }
            framing = .contentLength(length)
        } else {
            framing = .none
        }

        let expectsContinue = headers["expect"]?
            .lowercased()
            .contains("100-continue") ?? false

        let head = HTTPRequestHead(
            method: method,
            target: target,
            version: version,
            headers: headers,
            framing: framing,
            expectsContinue: expectsContinue
        )
        // consumed 是「字节数」而不是绝对下标（Data 切片可能从非 0 开始）
        return .complete(head, consumed: terminator.end - data.startIndex)
    }

    // MARK: 字符校验

    private static func isToken(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        for scalar in value.unicodeScalars {
            guard scalar.value < 128, isTokenScalar(scalar.value) else { return false }
        }
        return true
    }

    /// RFC 7230 tchar
    private static func isTokenScalar(_ value: UInt32) -> Bool {
        switch value {
        case 48...57, 65...90, 97...122: return true
        case 33, 35, 36, 37, 38, 39, 42, 43, 45, 46, 94, 95, 96, 124, 126: return true
        default: return false
        }
    }

    private static func isValidTarget(_ target: String) -> Bool {
        guard target.hasPrefix("/") else { return false }
        for scalar in target.unicodeScalars {
            // 排除空格、控制字符与 DEL
            if scalar.value <= 0x20 || scalar.value == 0x7F { return false }
        }
        return true
    }
}
