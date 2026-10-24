import Foundation
import Network
import ComicReaderCore

// MARK: - 一条 TCP 连接上的 HTTP 状态机
//
// 读 head → （上传时）把 body 逐块写进 .part 文件 → 通知服务端落位并响应。
// 下载走 send 完成回调串行泵文件块，天然带背压，不会把大文件塞进内存。
// 所有状态都在自己的串行队列上；对外方法可从任意线程调用。

/// 传输层共享上限
enum LanTransferLimits {
    /// 单个上传的体积上限（chunked 没有 Content-Length，必须在写入时兜底）
    static let maxUploadBytes: Int64 = 20 * 1024 * 1024 * 1024
}

/// 服务端对请求头的处置
enum LanTransferResponsePlan {
    /// 服务端已经发起了响应（页面 / JSON / 文件）
    case respondNow
    /// 把请求体流式写入这个临时文件；maxBytes 是本次上传的磁盘预留上限
    case receiveToFile(url: URL, expectedLength: Int64?, maxBytes: Int64)
    /// 直接拒绝
    case reject(status: HTTPStatus, message: String, headOnly: Bool)
}

protocol LanTransferConnectionDelegate: AnyObject {
    /// 在连接队列上调用；实现方必须同步决定处置并（除 receiveToFile 外）发起响应
    func transferConnection(
        _ connection: LanTransferConnection,
        handle head: HTTPRequestHead
    ) -> LanTransferResponsePlan

    /// 上传进度（已节流，约 5 次/秒）
    func transferConnection(_ connection: LanTransferConnection, uploadProgress bytes: Int64)

    /// 上传体接收完毕，文件在 fileURL；实现方负责移动到最终位置并响应
    func transferConnection(_ connection: LanTransferConnection, didFinishBodyAt fileURL: URL)

    /// 上传中断（连接断开 / 超时 / 写盘失败）；实现方负责清理状态
    func transferConnection(_ connection: LanTransferConnection, didAbort reason: String)

    /// 连接已关闭
    func transferConnectionDidClose(_ connection: LanTransferConnection)
}

final class LanTransferConnection: @unchecked Sendable {
    private static let idleTimeout: TimeInterval = 30
    /// 请求头必须在这么长时间内完成（防止慢速连接占满 16 个槽位）
    private static let headTimeout: TimeInterval = 10
    private static let receiveChunk = 64 * 1024
    private static let sendChunk = 1024 * 1024
    private static let progressInterval: TimeInterval = 0.2
    private static let queueKey = DispatchSpecificKey<Void>()

    private let nw: NWConnection
    private let queue: DispatchQueue
    private weak var delegate: LanTransferConnectionDelegate?

    private enum State: Equatable {
        case readingHead
        case receivingBody
        case responding
        case closed
    }

    private var state: State = .readingHead
    private var closed = false
    private var responseStarted = false
    private var peerClosed = false

    private var buffer = Data()
    private var remaining: Int64 = 0
    private var received: Int64 = 0
    private var bodyLimit: Int64 = LanTransferLimits.maxUploadBytes
    private var chunkDecoder: HTTPChunkedDecoder?

    private var bodyFileURL: URL?
    private var bodyHandle: FileHandle?
    private var bodyCommitted = false

    private var sendHandle: FileHandle?
    private var sendURL: URL?
    private var sendDeleteAfter = false

    private var lastProgressAt: TimeInterval = 0

    private lazy var idleTimer: DispatchSourceTimer = {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.idleTimeout)
        timer.setEventHandler { [weak self] in
            self?.abort("连接空闲超时")
        }
        timer.resume()
        return timer
    }()

    /// 请求头绝对截止时间（与按字节续期的 idleTimer 不同）
    private lazy var headTimer: DispatchSourceTimer = {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.headTimeout)
        timer.setEventHandler { [weak self] in
            self?.abort("请求头超时")
        }
        timer.resume()
        return timer
    }()

    init(connection: NWConnection, queue: DispatchQueue, delegate: LanTransferConnectionDelegate) {
        self.nw = connection
        self.queue = queue
        self.delegate = delegate
        queue.setSpecific(key: Self.queueKey, value: ())
    }

    // MARK: 生命周期

    func start() {
        onQueue {
            self.nw.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.receive()
                case .failed(let error):
                    self.abort("连接失败：\(error.localizedDescription)")
                case .cancelled:
                    self.finishClose()
                default:
                    break
                }
            }
            self.nw.start(queue: self.queue)
            self.touch()
            self.headTimer.schedule(deadline: .now() + Self.headTimeout)
        }
    }

    func cancel() {
        onQueue { self.abort("传输已停止") }
    }

    // MARK: 响应

    func respond(
        status: HTTPStatus,
        contentType: String? = nil,
        body: Data = Data(),
        extraHeaders: [(String, String)] = [],
        cacheControl: String = "no-store",
        headOnly: Bool = false
    ) {
        onQueue {
            self.sendResponse(
                status: status,
                contentType: contentType,
                body: body,
                extraHeaders: extraHeaders,
                cacheControl: cacheControl,
                headOnly: headOnly
            )
        }
    }

    func respondFile(
        url: URL,
        fileName: String,
        contentType: String,
        size: Int64,
        headOnly: Bool = false,
        deleteAfterSend: Bool = false
    ) {
        onQueue {
            self.sendFile(
                url: url,
                fileName: fileName,
                contentType: contentType,
                size: size,
                headOnly: headOnly,
                deleteAfterSend: deleteAfterSend
            )
        }
    }

    // MARK: 接收

    private func receive() {
        guard !closed, !responseStarted else { return }
        touch()
        nw.receive(
            minimumIncompleteLength: 1,
            maximumLength: Self.receiveChunk
        ) { [weak self] data, _, isComplete, error in
            guard let self, !self.closed else { return }
            if let error {
                self.abort("网络错误：\(error.localizedDescription)")
                return
            }
            if let data, !data.isEmpty {
                self.buffer.append(data)
            }
            self.touch()
            if isComplete { self.peerClosed = true }
            self.processBuffer()
        }
    }

    private func processBuffer() {
        guard !closed, !responseStarted else { return }

        if state == .readingHead {
            switch HTTPRequestHeadParser.parse(buffer) {
            case .incomplete:
                if peerClosed {
                    abort("连接在请求头完成前断开")
                } else {
                    receive()
                }
                return

            case .failure(let error):
                respondError(status: .badRequest, message: Self.message(for: error))
                return

            case .complete(let parsedHead, let consumed):
                buffer.removeFirst(consumed)
                headTimer.cancel()
                let plan = delegate?.transferConnection(self, handle: parsedHead)
                    ?? .reject(
                        status: .internalServerError,
                        message: "服务未就绪",
                        headOnly: parsedHead.isHeadRequest
                    )

                switch plan {
                case .respondNow:
                    // 服务端已发起响应，不再读取
                    return

                case .reject(let status, let message, let headOnly):
                    respondError(status: status, message: message, headOnly: headOnly)
                    return

                case .receiveToFile(let url, let expectedLength, let maxBytes):
                    do {
                        try openBodyFile(url)
                    } catch {
                        respondError(status: .internalServerError, message: "无法写入上传文件")
                        delegate?.transferConnection(self, didAbort: "无法写入上传文件")
                        return
                    }
                    bodyFileURL = url
                    bodyLimit = maxBytes
                    state = .receivingBody
                    if let expectedLength {
                        remaining = expectedLength
                    } else {
                        chunkDecoder = HTTPChunkedDecoder()
                    }
                    if parsedHead.expectsContinue {
                        nw.send(
                            content: HTTPResponseHead.continueResponse,
                            completion: .contentProcessed { _ in }
                        )
                    }
                    lastProgressAt = Date().timeIntervalSince1970
                    processBody()
                    return
                }
            }
        }

        if state == .receivingBody {
            processBody()
        }
    }

    private func processBody() {
        guard !closed, !responseStarted, state == .receivingBody else { return }

        if chunkDecoder != nil {
            var decoder = chunkDecoder!
            decoder.append(buffer)
            buffer.removeAll(keepingCapacity: true)

            while true {
                switch decoder.next() {
                case .needMoreData:
                    chunkDecoder = decoder
                    fetchMore()
                    return
                case .data(let chunk):
                    if !writeBody(chunk) {
                        chunkDecoder = decoder
                        return
                    }
                case .finished:
                    chunkDecoder = decoder
                    finishBody()
                    return
                case .failure(let error):
                    chunkDecoder = decoder
                    failBody("分块传输格式错误（\(error)）", status: .badRequest)
                    return
                }
            }
        }

        let available = Int64(buffer.count)
        let take = Swift.min(remaining, available)
        if take > 0 {
            let chunk = Data(buffer.prefix(Int(take)))
            buffer.removeFirst(Int(take))
            if !writeBody(chunk) { return }
            remaining -= take
        }

        if remaining == 0 {
            finishBody()
        } else {
            fetchMore()
        }
    }

    private func fetchMore() {
        if peerClosed {
            abort("连接已断开，上传未完成")
        } else {
            receive()
        }
    }

    private func writeBody(_ data: Data) -> Bool {
        guard let handle = bodyHandle else { return false }
        if received + Int64(data.count) > bodyLimit {
            if bodyLimit < LanTransferLimits.maxUploadBytes {
                failBody("手机存储空间不足", status: .insufficientStorage)
            } else {
                failBody("文件过大（上限 20 GB）", status: .payloadTooLarge)
            }
            return false
        }
        do {
            try handle.write(contentsOf: data)
            received += Int64(data.count)
            reportProgressIfNeeded(force: false)
            return true
        } catch {
            failBody("写入文件失败：\(error.localizedDescription)", status: .internalServerError)
            return false
        }
    }

    private func reportProgressIfNeeded(force: Bool) {
        let now = Date().timeIntervalSince1970
        guard force || now - lastProgressAt >= Self.progressInterval else { return }
        lastProgressAt = now
        delegate?.transferConnection(self, uploadProgress: received)
    }

    private func finishBody() {
        guard state == .receivingBody else { return }
        reportProgressIfNeeded(force: true)
        try? bodyHandle?.close()
        bodyHandle = nil
        state = .responding
        bodyCommitted = true

        guard let url = bodyFileURL else {
            respondError(status: .internalServerError, message: "上传文件丢失")
            delegate?.transferConnection(self, didAbort: "上传文件丢失")
            return
        }
        bodyFileURL = nil
        delegate?.transferConnection(self, didFinishBodyAt: url)
    }

    private func failBody(_ message: String, status: HTTPStatus) {
        guard !closed else { return }
        try? bodyHandle?.close()
        bodyHandle = nil
        let url = bodyFileURL
        bodyFileURL = nil
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
        respondError(status: status, message: message)
        delegate?.transferConnection(self, didAbort: message)
    }

    private func openBodyFile(_ url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: url)
        }
        guard fm.createFile(atPath: url.path, contents: nil) else {
            throw NSError(domain: "LanTransfer", code: 1)
        }
        bodyHandle = try FileHandle(forWritingTo: url)
    }

    // MARK: 发送

    private func sendResponse(
        status: HTTPStatus,
        contentType: String?,
        body: Data,
        extraHeaders: [(String, String)],
        cacheControl: String,
        headOnly: Bool
    ) {
        guard !closed, !responseStarted else { return }
        responseStarted = true
        state = .responding
        headTimer.cancel()

        var headers: [(String, String)] = [
            ("Connection", "close"),
            ("Cache-Control", cacheControl),
            ("X-Content-Type-Options", "nosniff"),
            ("Referrer-Policy", "no-referrer"),
        ]
        if let contentType {
            headers.append(("Content-Type", contentType))
        }
        headers.append(contentsOf: extraHeaders)

        let head = HTTPResponseHead.serialize(
            status: status,
            headers: headers,
            contentLength: body.count
        )
        let payload = headOnly ? head : head + body
        nw.send(
            content: payload,
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { [weak self] _ in
                self?.finishClose()
            }
        )
    }

    private func respondError(status: HTTPStatus, message: String, headOnly: Bool = false) {
        let body = (try? JSONEncoder().encode(LanTransferErrorBody(error: message)))
            ?? Data("{\"error\":\"error\"}".utf8)
        respond(
            status: status,
            contentType: "application/json; charset=utf-8",
            body: body,
            headOnly: headOnly
        )
    }

    private func sendFile(
        url: URL,
        fileName: String,
        contentType: String,
        size: Int64,
        headOnly: Bool,
        deleteAfterSend: Bool
    ) {
        guard !closed, !responseStarted else {
            if deleteAfterSend { try? FileManager.default.removeItem(at: url) }
            return
        }

        // 打开文件失败时还没开始响应，可以直接回 404
        var readHandle: FileHandle?
        if !headOnly {
            guard let handle = try? FileHandle(forReadingFrom: url) else {
                if deleteAfterSend { try? FileManager.default.removeItem(at: url) }
                respondError(status: .notFound, message: "文件不存在")
                return
            }
            readHandle = handle
        }

        responseStarted = true
        state = .responding
        headTimer.cancel()
        sendHandle = readHandle
        sendURL = url
        sendDeleteAfter = deleteAfterSend
        touch()

        let headers: [(String, String)] = [
            ("Connection", "close"),
            ("Cache-Control", "no-store"),
            ("X-Content-Type-Options", "nosniff"),
            ("Referrer-Policy", "no-referrer"),
            ("Content-Type", contentType),
            ("Content-Disposition", TransferNaming.contentDisposition(fileName: fileName)),
            ("Accept-Ranges", "none"),
        ]
        let head = HTTPResponseHead.serialize(
            status: .ok,
            headers: headers,
            contentLength: Int(size)
        )

        if headOnly {
            nw.send(
                content: head,
                contentContext: .finalMessage,
                isComplete: true,
                completion: .contentProcessed { [weak self] _ in
                    self?.cleanupFileTransfer()
                    self?.finishClose()
                }
            )
            return
        }

        nw.send(content: head, completion: .contentProcessed { [weak self] error in
            if error != nil {
                self?.finishFileTransfer()
            } else {
                self?.pumpFile()
            }
        })
    }

    private func pumpFile() {
        guard !closed, state == .responding, let handle = sendHandle else { return }
        touch()

        let chunk: Data?
        do {
            chunk = try handle.read(upToCount: Self.sendChunk)
        } catch {
            finishFileTransfer()
            return
        }

        if let chunk, !chunk.isEmpty {
            nw.send(content: chunk, completion: .contentProcessed { [weak self] error in
                if error != nil {
                    self?.finishFileTransfer()
                } else {
                    self?.pumpFile()
                }
            })
            return
        }

        nw.send(
            content: nil,
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { [weak self] _ in
                self?.cleanupFileTransfer()
                self?.finishClose()
            }
        )
    }

    private func finishFileTransfer() {
        cleanupFileTransfer()
        finishClose()
    }

    private func cleanupFileTransfer() {
        try? sendHandle?.close()
        sendHandle = nil
        if sendDeleteAfter, let url = sendURL {
            try? FileManager.default.removeItem(at: url)
        }
        sendURL = nil
        sendDeleteAfter = false
    }

    // MARK: 关闭

    private func abort(_ reason: String) {
        guard !closed else { return }
        let pendingURL = bodyFileURL
        let committed = bodyCommitted

        closed = true
        state = .closed
        responseStarted = true
        idleTimer.cancel()
        headTimer.cancel()

        try? bodyHandle?.close()
        bodyHandle = nil
        cleanupFileTransfer()
        if !committed, let pendingURL {
            try? FileManager.default.removeItem(at: pendingURL)
        }
        bodyFileURL = nil

        nw.cancel()
        delegate?.transferConnection(self, didAbort: reason)
        delegate?.transferConnectionDidClose(self)
    }

    private func finishClose() {
        guard !closed else { return }
        closed = true
        state = .closed
        responseStarted = true
        idleTimer.cancel()
        headTimer.cancel()

        try? bodyHandle?.close()
        bodyHandle = nil
        cleanupFileTransfer()
        if !bodyCommitted, let url = bodyFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        bodyFileURL = nil

        nw.cancel()
        delegate?.transferConnectionDidClose(self)
    }

    // MARK: 工具

    private func touch() {
        guard !closed else { return }
        idleTimer.schedule(deadline: .now() + Self.idleTimeout)
    }

    private func onQueue(_ body: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            body()
        } else {
            queue.async { body() }
        }
    }

    private static func message(for error: HTTPHeadError) -> String {
        switch error {
        case .headTooLarge:
            return "请求头过大"
        case .malformedRequestLine, .malformedHeader:
            return "请求格式错误"
        case .unsupportedVersion:
            return "不支持的 HTTP 版本"
        case .invalidContentLength, .conflictingContentLength:
            return "Content-Length 不合法"
        case .ambiguousBodyFraming:
            return "请求体分帧不明确"
        case .unsupportedTransferEncoding:
            return "不支持的 Transfer-Encoding"
        }
    }
}

private struct LanTransferErrorBody: Encodable {
    let error: String
}
