import Foundation

// MARK: - HTTP chunked 解码（局域网传输）
//
// 浏览器在请求体长度未知时会用 Transfer-Encoding: chunked。这里是一个
// 可增量喂入的状态机：任意字节边界（甚至逐字节）调用 append + next 都能正确解码。
// 只依赖 Foundation，便于在 Windows 上类型检查、在 macOS CI 上单测。

public enum HTTPChunkError: Error, Equatable, Sendable {
    case lineTooLong
    case invalidChunkSize
    case chunkTooLarge
    case malformedChunkTerminator
    case malformedTrailer
    case trailerTooLong
}

public struct HTTPChunkedDecoder: Sendable {
    public enum Output: Equatable, Sendable {
        /// 当前数据不够，继续 append 后再调用 next
        case needMoreData
        /// 一段解码后的 body 字节（可能小于一个完整 chunk）
        case data(Data)
        /// 整个 chunked body 结束（含零长度 chunk 与可选 trailers）
        case finished
        case failure(HTTPChunkError)
    }

    private enum State {
        case size
        case data
        case dataCRLF
        case trailers
    }

    private enum LineResult {
        case line(String)
        case needMore
        case tooLong
    }

    private enum ChunkSizeResult {
        case value(Int)
        case invalid
        case tooLarge
    }

    private var buffer = Data()
    private var offset = 0
    private var state: State = .size
    private var remaining = 0
    private var trailerBytes = 0

    public init() {}

    /// 追加从网络读到的原始字节
    public mutating func append(_ data: Data) {
        compactIfNeeded(force: false)
        buffer.append(data)
    }

    /// 尚未消费的原始字节数（调试 / 测试用）
    public var bufferedByteCount: Int { buffer.count - offset }

    /// 取出下一段可写出的数据；调用方应循环调用直到 needMoreData / finished / failure
    public mutating func next() -> Output {
        while true {
            switch state {
            case .size:
                switch takeLine() {
                case .needMore:
                    return .needMoreData
                case .tooLong:
                    return .failure(.lineTooLong)
                case .line(let line):
                    switch parseChunkSize(line) {
                    case .invalid:
                        return .failure(.invalidChunkSize)
                    case .tooLarge:
                        return .failure(.chunkTooLarge)
                    case .value(let size):
                        if size == 0 {
                            state = .trailers
                            trailerBytes = 0
                        } else {
                            remaining = size
                            state = .data
                        }
                    }
                }

            case .data:
                let available = buffer.count - offset
                if available == 0 { return .needMoreData }
                let take = Swift.min(remaining, available)
                let chunk = Data(buffer[offset..<(offset + take)])
                offset += take
                remaining -= take
                if remaining == 0 { state = .dataCRLF }
                compactIfNeeded(force: false)
                if !chunk.isEmpty { return .data(chunk) }

            case .dataCRLF:
                let available = buffer.count - offset
                guard available > 0 else { return .needMoreData }
                if buffer[offset] == 13 {
                    guard available >= 2 else { return .needMoreData }
                    guard buffer[offset + 1] == 10 else {
                        return .failure(.malformedChunkTerminator)
                    }
                    offset += 2
                } else if buffer[offset] == 10 {
                    // 容忍裸 LF
                    offset += 1
                } else {
                    return .failure(.malformedChunkTerminator)
                }
                compactIfNeeded(force: false)
                state = .size

            case .trailers:
                let available = buffer.count - offset
                if available > 0 {
                    // 空行 = trailers 结束
                    if buffer[offset] == 13 {
                        guard available >= 2 else { return .needMoreData }
                        if buffer[offset + 1] == 10 {
                            offset += 2
                            compactIfNeeded(force: true)
                            return .finished
                        }
                    } else if buffer[offset] == 10 {
                        offset += 1
                        compactIfNeeded(force: true)
                        return .finished
                    }
                }
                switch takeLine() {
                case .needMore:
                    return .needMoreData
                case .tooLong:
                    return .failure(.trailerTooLong)
                case .line(let line):
                    if line.isEmpty {
                        return .finished
                    }
                    trailerBytes += line.utf8.count + 2
                    guard trailerBytes <= HTTPLimits.maxChunkLineBytes else {
                        return .failure(.trailerTooLong)
                    }
                    // trailer 内容用不到，但必须是合法的 header 行
                    guard line.contains(":") else {
                        return .failure(.malformedTrailer)
                    }
                }
            }
        }
    }

    // MARK: 内部

    private mutating func takeLine() -> LineResult {
        let available = buffer.count - offset
        guard available > 0 else { return .needMore }
        var index = offset
        while index < buffer.count {
            if buffer[index] == 10 {
                var lineEnd = index
                if lineEnd > offset, buffer[lineEnd - 1] == 13 {
                    lineEnd -= 1
                }
                let line = String(decoding: buffer[offset..<lineEnd], as: UTF8.self)
                offset = index + 1
                compactIfNeeded(force: false)
                return .line(line)
            }
            if index - offset > HTTPLimits.maxChunkLineBytes {
                return .tooLong
            }
            index += 1
        }
        if available > HTTPLimits.maxChunkLineBytes {
            return .tooLong
        }
        return .needMore
    }

    private func parseChunkSize(_ line: String) -> ChunkSizeResult {
        // chunk 扩展（;name=value）忽略
        let sizePart = line
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? ""
        let hex = sizePart.trimmingCharacters(in: .whitespaces)
        guard !hex.isEmpty, hex.utf8.allSatisfy(isHexDigit) else {
            return .invalid
        }
        guard let value = UInt64(hex, radix: 16) else {
            return .tooLarge
        }
        guard value <= UInt64(HTTPLimits.maxChunkBytes) else {
            return .tooLarge
        }
        return .value(Int(value))
    }

    private func isHexDigit(_ byte: UInt8) -> Bool {
        (byte >= 48 && byte <= 57)     // 0-9
            || (byte >= 65 && byte <= 70)  // A-F
            || (byte >= 97 && byte <= 102) // a-f
    }

    /// 已消费前缀攒到 64 KiB 或全部消费完时，把缓冲区前移，避免无限增长
    private mutating func compactIfNeeded(force: Bool) {
        if offset == buffer.count {
            buffer.removeAll(keepingCapacity: true)
            offset = 0
        } else if force || offset >= 64 * 1024 {
            buffer = Data(buffer[offset...])
            offset = 0
        }
    }
}
