import ComicReaderCore
import Foundation
import Network

// MARK: - 局域网传输 HTTP 服务
//
// NWListener 监听 [8765, 8766, 8767, 任意端口]，每个 TCP 连接交给
// LanTransferConnection 处理。这里只负责：鉴权、路由、上传落位、响应。
//
// 安全边界：
//   - 6 位密码写在路径首段；连续错 10 次自动停服（由模型弹提示）
//   - 上传文件名白名单 + 净化；下载只按书库 id 反查，不接受路径
//   - 每个响应 Connection: close，不做 keep-alive，避免请求走私复杂度

struct LanTransferUploadReady: Sendable {
    let id: String
    let name: String
    let size: Int64
    let destination: String
}

enum LanTransferServerError: LocalizedError {
    case noPortAvailable
    case listenFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPortAvailable:
            return "找不到可用的监听端口"
        case .listenFailed(let message):
            return message
        }
    }
}

final class LanTransferServer: @unchecked Sendable {
    static let maxConnections = 16

    private static let serverQueueKey = DispatchSpecificKey<Void>()
    private static let pageHeaders: [(String, String)] = [
        (
            "Content-Security-Policy",
            "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; "
                + "script-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; form-action 'self'"
        ),
        ("X-Frame-Options", "DENY"),
    ]

    private struct PendingUpload {
        let id: String
        let name: String
        let partURL: URL
        /// 本次上传占用的磁盘预留（chunked 没有 Content-Length，按当前可用空间整体预留）
        let reservedBytes: Int64
    }

    private let queue = DispatchQueue(label: "com.comicreader.lan-transfer.server")
    private let deviceName: String
    private let paths: AppPaths
    private let library: LanTransferLibrary
    private let statusStore: LanTransferStatusStore

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: LanTransferConnection] = [:]
    private let pendingLock = NSLock()
    private var pendingUploads: [ObjectIdentifier: PendingUpload] = [:]
    private var stopped = false

    private(set) var port: UInt16 = 0

    var onUploadReady: (@Sendable (LanTransferUploadReady) -> Void)?
    var onConnectionCountChanged: (@Sendable (Int) -> Void)?
    var onListenerFailed: (@Sendable (String) -> Void)?

    init(
        deviceName: String,
        paths: AppPaths,
        library: LanTransferLibrary,
        statusStore: LanTransferStatusStore
    ) {
        self.deviceName = deviceName
        self.paths = paths
        self.library = library
        self.statusStore = statusStore
        queue.setSpecific(key: Self.serverQueueKey, value: ())
    }

    // MARK: 启停

    func start(preferredPorts: [UInt16] = [8765, 8766, 8767, 0]) async throws -> UInt16 {
        // 上次异常退出可能留下 .part 文件
        cleanInbox()

        var lastError: Error = LanTransferServerError.noPortAvailable
        for candidate in preferredPorts {
            do {
                let actual = try await startListener(on: candidate)
                port = actual
                return actual
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func stop() {
        if DispatchQueue.getSpecific(key: Self.serverQueueKey) != nil {
            stopLocked()
        } else {
            queue.sync { stopLocked() }
        }
    }

    private func stopLocked() {
        let firstStop = !stopped
        stopped = true

        // 即使已经停过一次，也要取消可能「迟到」的 listener：
        // 启动过程中 stop，ready 回调可能在第一次 stop 之后才把 listener 挂上来。
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil

        guard firstStop else { return }

        let current = connections
        connections.removeAll()
        for (_, connection) in current {
            connection.cancel()
        }

        pendingLock.lock()
        pendingUploads.removeAll()
        pendingLock.unlock()

        statusStore.failReceiving(reason: "传输已停止")
        cleanInbox()
        onConnectionCountChanged?(0)
    }

    private func startListener(on candidate: UInt16) async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let endpointPort: NWEndpoint.Port
        if candidate == 0 {
            endpointPort = .any
        } else {
            guard let value = NWEndpoint.Port(rawValue: candidate) else {
                throw LanTransferServerError.listenFailed("端口不合法")
            }
            endpointPort = value
        }

        let listener = try NWListener(using: parameters, on: endpointPort)
        let gate = ResumeGate()

        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    let actual = listener.port?.rawValue ?? candidate
                    if gate.claim() {
                        self?.queue.async {
                            self?.listener = listener
                        }
                        continuation.resume(returning: actual)
                    }

                case .failed(let error):
                    if gate.claim() {
                        listener.stateUpdateHandler = nil
                        listener.newConnectionHandler = nil
                        listener.cancel()
                        continuation.resume(
                            throwing: LanTransferServerError.listenFailed(error.localizedDescription)
                        )
                    } else {
                        self?.queue.async {
                            self?.handleListenerFailure(error.localizedDescription)
                        }
                    }

                case .waiting(let error):
                    if gate.claim() {
                        listener.stateUpdateHandler = nil
                        listener.newConnectionHandler = nil
                        listener.cancel()
                        continuation.resume(
                            throwing: LanTransferServerError.listenFailed(error.localizedDescription)
                        )
                    }

                case .cancelled:
                    if gate.claim() {
                        continuation.resume(
                            throwing: LanTransferServerError.listenFailed("监听已取消")
                        )
                    }

                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: self.queue)

            // 端口被占用时 .failed 通常很快；兜底 2 秒超时后换下一个端口
            self.queue.asyncAfter(deadline: .now() + 2) {
                if gate.claim() {
                    listener.stateUpdateHandler = nil
                    listener.newConnectionHandler = nil
                    listener.cancel()
                    continuation.resume(
                        throwing: LanTransferServerError.listenFailed("监听超时")
                    )
                }
            }
        }
    }

    private func handleListenerFailure(_ message: String) {
        guard !stopped else { return }
        stopLocked()
        onListenerFailed?(message)
    }

    private func accept(_ connection: NWConnection) {
        guard !stopped else {
            connection.cancel()
            return
        }
        guard connections.count < Self.maxConnections else {
            connection.cancel()
            return
        }

        let connectionQueue = DispatchQueue(label: "com.comicreader.lan-transfer.conn.\(UUID().uuidString)")
        let wrapped = LanTransferConnection(
            connection: connection,
            queue: connectionQueue,
            delegate: self
        )
        connections[ObjectIdentifier(wrapped)] = wrapped
        onConnectionCountChanged?(connections.count)
        wrapped.start()
    }

    // MARK: 上传状态

    /// 在锁内检查磁盘容量并登记预留：并发上传不会各自看到「全部空闲空间」。
    /// 返回本次上传允许的最大字节数；空间不足返回 nil。
    private func beginUpload(
        connection: LanTransferConnection,
        id: String,
        name: String,
        partURL: URL,
        expected: Int64?
    ) -> Int64? {
        pendingLock.lock()
        defer { pendingLock.unlock() }

        let reserved = pendingUploads.values.reduce(Int64(0)) { $0 + $1.reservedBytes }
        let capacity = availableCapacity()
        let usable = capacity.map { max(0, $0 - 64 * 1024 * 1024 - reserved) }

        let reservedBytes: Int64
        if let expected {
            if let usable, usable < expected { return nil }
            reservedBytes = expected
        } else {
            let limit = min(
                LanTransferLimits.maxUploadBytes,
                usable ?? LanTransferLimits.maxUploadBytes
            )
            guard limit > 0 else { return nil }
            reservedBytes = limit
        }

        pendingUploads[ObjectIdentifier(connection)] = PendingUpload(
            id: id,
            name: name,
            partURL: partURL,
            reservedBytes: reservedBytes
        )
        return reservedBytes
    }

    private func peekPending(_ connection: LanTransferConnection) -> PendingUpload? {
        pendingLock.lock()
        defer { pendingLock.unlock() }
        return pendingUploads[ObjectIdentifier(connection)]
    }

    private func takePending(_ connection: LanTransferConnection) -> PendingUpload? {
        pendingLock.lock()
        defer { pendingLock.unlock() }
        return pendingUploads.removeValue(forKey: ObjectIdentifier(connection))
    }

    // MARK: 路径

    private var inboxDirPath: String {
        (paths.comicsDir as NSString).appendingPathComponent(".lan-inbox")
    }

    private func cleanInbox() {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: inboxDirPath) else { return }
        for name in names {
            try? fm.removeItem(atPath: (inboxDirPath as NSString).appendingPathComponent(name))
        }
    }

    private func availableCapacity() -> Int64? {
        let url = URL(fileURLWithPath: paths.comicsDir)
        if let values = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ), let available = values.volumeAvailableCapacityForImportantUsage {
            return available
        }
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
           let available = values.volumeAvailableCapacity {
            return Int64(available)
        }
        return nil
    }

    private func errorJSON(_ message: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["error": message]))
            ?? Data("{\"error\":\"error\"}".utf8)
    }

    private func stateJSON() -> Data {
        let uploads: [[String: Any]] = statusStore.snapshot().map { item in
            var dict: [String: Any] = [
                "id": item.id,
                "name": item.name,
                "size": item.size,
                "received": item.received,
                "state": item.state.rawValue,
            ]
            if let reason = item.reason {
                dict["reason"] = reason
            }
            return dict
        }
        let payload: [String: Any] = [
            "device": deviceName,
            "libraryCount": library.count(),
            "uploads": uploads,
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
    }

    private static func fileSize(_ path: String) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func isReadMethod(_ head: HTTPRequestHead) -> Bool {
        head.method == "GET" || head.method == "HEAD"
    }
}

// MARK: - 路由与响应

extension LanTransferServer: LanTransferConnectionDelegate {
    func transferConnection(
        _ connection: LanTransferConnection,
        handle head: HTTPRequestHead
    ) -> LanTransferResponsePlan {
        let route = TransferRoute.parse(head.target)

        switch route {
        case .landing:
            guard isReadMethod(head) else {
                return .reject(
                    status: .methodNotAllowed,
                    message: "只支持 GET / HEAD",
                    headOnly: head.isHeadRequest
                )
            }
            let page = TransferWebPage.app(
                deviceName: deviceName,
                libraryCount: library.count()
            )
            connection.respond(
                status: .ok,
                contentType: "text/html; charset=utf-8",
                body: Data(page.utf8),
                extraHeaders: Self.pageHeaders,
                headOnly: head.isHeadRequest
            )
            return .respondNow

        case .state:
            guard isReadMethod(head) else {
                return .reject(
                    status: .methodNotAllowed,
                    message: "只支持 GET / HEAD",
                    headOnly: head.isHeadRequest
                )
            }
            connection.respond(
                status: .ok,
                contentType: "application/json; charset=utf-8",
                body: stateJSON(),
                headOnly: head.isHeadRequest
            )
            return .respondNow

        case .library:
            guard isReadMethod(head) else {
                return .reject(
                    status: .methodNotAllowed,
                    message: "只支持 GET / HEAD",
                    headOnly: head.isHeadRequest
                )
            }
            connection.respond(
                status: .ok,
                contentType: "application/json; charset=utf-8",
                body: library.libraryJSON(),
                headOnly: head.isHeadRequest
            )
            return .respondNow

        case .cover(let id):
            guard isReadMethod(head) else {
                return .reject(
                    status: .methodNotAllowed,
                    message: "只支持 GET / HEAD",
                    headOnly: head.isHeadRequest
                )
            }
            do {
                let cover = try library.cover(id: id)
                connection.respond(
                    status: .ok,
                    contentType: cover.contentType,
                    body: cover.data,
                    cacheControl: "max-age=3600",
                    headOnly: head.isHeadRequest
                )
            } catch {
                connection.respond(
                    status: .notFound,
                    contentType: "application/json; charset=utf-8",
                    body: errorJSON("没有封面"),
                    headOnly: head.isHeadRequest
                )
            }
            return .respondNow

        case .download(let id):
            guard isReadMethod(head) else {
                return .reject(
                    status: .methodNotAllowed,
                    message: "只支持 GET / HEAD",
                    headOnly: head.isHeadRequest
                )
            }
            do {
                let download = try library.makeDownload(id: id)
                connection.respondFile(
                    url: download.url,
                    fileName: download.fileName,
                    contentType: download.contentType,
                    size: download.size,
                    headOnly: head.isHeadRequest,
                    deleteAfterSend: download.deleteAfterSend
                )
            } catch {
                connection.respond(
                    status: .notFound,
                    contentType: "application/json; charset=utf-8",
                    body: errorJSON(error.localizedDescription),
                    headOnly: head.isHeadRequest
                )
            }
            return .respondNow

        case .upload(let fileName):
            return handleUpload(connection, head: head, fileName: fileName)

        case .notFound:
            return .reject(
                status: .notFound,
                message: "接口不存在",
                headOnly: head.isHeadRequest
            )
        }
    }

    func transferConnection(_ connection: LanTransferConnection, uploadProgress bytes: Int64) {
        guard let pending = peekPending(connection) else { return }
        statusStore.updateProgress(id: pending.id, received: bytes)
    }

    func transferConnection(_ connection: LanTransferConnection, didFinishBodyAt fileURL: URL) {
        guard let pending = takePending(connection) else {
            try? FileManager.default.removeItem(at: fileURL)
            connection.respond(
                status: .internalServerError,
                contentType: "application/json; charset=utf-8",
                body: errorJSON("上传状态丢失，请重试")
            )
            return
        }

        let fm = FileManager.default
        let size = Self.fileSize(fileURL.path)
        guard size > 0 else {
            try? fm.removeItem(at: fileURL)
            statusStore.fail(id: pending.id, reason: "文件为空")
            connection.respond(
                status: .badRequest,
                contentType: "application/json; charset=utf-8",
                body: errorJSON("文件为空")
            )
            return
        }

        var destinationName = ""
        var destinationPath = ""
        var moved = false
        var lastError: Error?

        // 并发上传同名文件时，uniqueFileName 的结果可能被另一个连接抢先占用，
        // moveItem 会失败；换下一个序号重试几次即可。
        for _ in 0..<8 {
            let candidate = TransferNaming.uniqueFileName(preferred: pending.name) { name in
                let path = (paths.comicsDir as NSString).appendingPathComponent(name)
                return fm.fileExists(atPath: path)
            }
            let path = (paths.comicsDir as NSString).appendingPathComponent(candidate)
            do {
                try fm.moveItem(at: fileURL, to: URL(fileURLWithPath: path))
                destinationName = candidate
                destinationPath = path
                moved = true
                break
            } catch {
                lastError = error
                if fm.fileExists(atPath: path) { continue }
                break
            }
        }

        guard moved else {
            try? fm.removeItem(at: fileURL)
            let reason = lastError?.localizedDescription ?? "未知错误"
            statusStore.fail(id: pending.id, reason: "保存失败：\(reason)")
            connection.respond(
                status: .internalServerError,
                contentType: "application/json; charset=utf-8",
                body: errorJSON("保存上传文件失败")
            )
            return
        }

        statusStore.finishReceiving(
            id: pending.id,
            size: size,
            name: destinationName,
            state: .importing
        )
        onUploadReady?(
            LanTransferUploadReady(
                id: pending.id,
                name: destinationName,
                size: size,
                destination: destinationPath
            )
        )

        let response: [String: Any] = [
            "id": pending.id,
            "name": destinationName,
            "size": size,
        ]
        let body = (try? JSONSerialization.data(withJSONObject: response)) ?? Data("{}".utf8)
        connection.respond(
            status: .ok,
            contentType: "application/json; charset=utf-8",
            body: body
        )
    }

    func transferConnection(_ connection: LanTransferConnection, didAbort reason: String) {
        guard let pending = takePending(connection) else { return }
        try? FileManager.default.removeItem(at: pending.partURL)
        statusStore.fail(id: pending.id, reason: reason)
    }

    func transferConnectionDidClose(_ connection: LanTransferConnection) {
        queue.async { [weak self] in
            guard let self else { return }
            self.connections.removeValue(forKey: ObjectIdentifier(connection))
            self.onConnectionCountChanged?(self.connections.count)
        }
    }

    // MARK: 上传

    private func handleUpload(
        _ connection: LanTransferConnection,
        head: HTTPRequestHead,
        fileName: String?
    ) -> LanTransferResponsePlan {
        guard head.method == "PUT" || head.method == "POST" else {
            return .reject(status: .methodNotAllowed, message: "只支持 PUT / POST", headOnly: head.isHeadRequest)
        }

        if let contentType = head.header("content-type")?.lowercased(),
           contentType.hasPrefix("multipart/") {
            return .reject(
                status: .badRequest,
                message: "请使用页面上的上传入口（不支持表单上传）",
                headOnly: head.isHeadRequest
            )
        }

        guard let rawName = fileName, !rawName.isEmpty else {
            return .reject(status: .badRequest, message: "缺少文件名", headOnly: head.isHeadRequest)
        }
        guard let name = TransferNaming.sanitizeFileName(rawName) else {
            return .reject(status: .badRequest, message: "文件名不合法或过长", headOnly: head.isHeadRequest)
        }
        guard TransferNaming.isAllowedComicFile(name) else {
            return .reject(
                status: .badRequest,
                message: "只支持 ZIP / CBZ / RAR / CBR / PDF",
                headOnly: head.isHeadRequest
            )
        }

        let expected: Int64?
        switch head.framing {
        case .contentLength(let length):
            guard length > 0 else {
                return .reject(status: .badRequest, message: "文件为空", headOnly: head.isHeadRequest)
            }
            guard Int64(length) <= LanTransferLimits.maxUploadBytes else {
                return .reject(status: .payloadTooLarge, message: "文件过大（上限 20 GB）", headOnly: head.isHeadRequest)
            }
            expected = Int64(length)
        case .chunked:
            expected = nil
        case .none:
            return .reject(status: .lengthRequired, message: "缺少 Content-Length", headOnly: head.isHeadRequest)
        }

        let id = UUID().uuidString.lowercased()
        let partURL = URL(fileURLWithPath: inboxDirPath)
            .appendingPathComponent("\(id).part")

        guard let maxBytes = beginUpload(
            connection: connection,
            id: id,
            name: name,
            partURL: partURL,
            expected: expected
        ) else {
            return .reject(status: .insufficientStorage, message: "手机存储空间不足", headOnly: head.isHeadRequest)
        }

        statusStore.begin(id: id, name: name, size: expected ?? 0)
        return .receiveToFile(url: partURL, expectedLength: expected, maxBytes: maxBytes)
    }
}

// MARK: - 仅允许一次 resume

private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
