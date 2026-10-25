import ComicReaderCore
import Foundation
import UIKit

// MARK: - 局域网传输状态（SwiftUI 观察）
//
// 负责：启停服务、显示地址/密码/记录、自动导入队列、进入后台停服。
// 服务器回调来自各自的连接队列，统一经 Task { @MainActor } 回到这里。
// 「传完自动导入」只存 UserDefaults，不写 library.json（桌面版不认识这个键）。

@MainActor
final class LanTransferModel: ObservableObject {
    enum Phase: Equatable {
        case stopped
        case starting
        case running
        case failed(String)
    }

    static let autoImportKey = "lanTransfer.autoImport"
    static let preferredPorts: [UInt16] = [8765, 8766, 8767, 0]

    @Published private(set) var phase: Phase = .stopped
    @Published private(set) var urlString: String?
    @Published private(set) var port: UInt16 = 0
    @Published private(set) var ipAddress: String?
    @Published private(set) var recent: [LanTransferStatusStore.Item] = []
    @Published private(set) var connectionCount = 0

    /// 传完自动导入书架
    @Published var autoImport: Bool {
        didSet { defaults.set(autoImport, forKey: Self.autoImportKey) }
    }

    private let paths: AppPaths
    private let db: LibraryDatabase
    private let shelf: ShelfStore
    private let toasts: ToastCenter
    private let defaults: UserDefaults

    private var server: LanTransferServer?
    private var statusStore: LanTransferStatusStore?
    private var generation = 0
    private var idleTimerHeld = false
    private var previousIdleTimerDisabled = false

    private struct PendingImport {
        let id: String
        let name: String
        let destination: String
    }

    private var pendingImports: [PendingImport] = []
    private var importFlushScheduled = false
    private var importing = false

    init(
        paths: AppPaths,
        db: LibraryDatabase,
        shelf: ShelfStore,
        toasts: ToastCenter,
        defaults: UserDefaults = .standard
    ) {
        self.paths = paths
        self.db = db
        self.shelf = shelf
        self.toasts = toasts
        self.defaults = defaults
        self.autoImport = (defaults.object(forKey: Self.autoImportKey) as? Bool) ?? true
    }

    // MARK: 启停

    func start() async {
        guard phase != .running, phase != .starting else { return }
        generation += 1
        let generationAtStart = generation
        phase = .starting

        guard let ip = LocalAddress.primaryIPv4() else {
            phase = .failed("请先连接 Wi-Fi（或打开个人热点）")
            return
        }

        let store = LanTransferStatusStore()
        store.onChange = { [weak self] in
            Task { @MainActor in self?.refreshRecent() }
        }

        let library = LanTransferLibrary(
            db: db,
            coversDir: paths.coversDir,
            comicsDir: paths.comicsDir
        )
        let server = LanTransferServer(
            deviceName: UIDevice.current.name,
            paths: paths,
            library: library,
            statusStore: store
        )

        server.onUploadReady = { [weak self] ready in
            Task { @MainActor in self?.handleUploadReady(ready) }
        }
        server.onConnectionCountChanged = { [weak self] count in
            Task { @MainActor in self?.connectionCount = count }
        }
        server.onListenerFailed = { [weak self] message in
            Task { @MainActor in self?.handleListenerFailure(message) }
        }

        do {
            let actualPort = try await server.start(preferredPorts: Self.preferredPorts)
            guard generation == generationAtStart, phase == .starting else {
                server.stop()
                return
            }

            self.server = server
            self.statusStore = store
            self.port = actualPort
            self.ipAddress = ip
            self.urlString = "http://\(ip):\(actualPort)/"
            self.recent = store.snapshot()
            self.connectionCount = 0
            self.phase = .running

            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            idleTimerHeld = true
        } catch {
            server.stop()
            guard generation == generationAtStart else { return }
            phase = .failed("启动失败：\(error.localizedDescription)")
        }
    }

    func stop(notify: Bool = false, reason: String? = nil) {
        generation += 1
        let wasActive = phase == .running || phase == .starting

        server?.stop()
        server = nil
        statusStore = nil
        urlString = nil
        connectionCount = 0
        phase = .stopped

        if idleTimerHeld {
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
            idleTimerHeld = false
        }

        if notify, wasActive {
            toasts.show(.info, reason ?? "局域网传输已停止")
        }
    }

    /// App 进入后台：iOS 会挂起进程，监听留着也收不到包，直接停掉并告知
    func handleBackground() {
        guard phase == .running || phase == .starting else { return }
        stop(notify: true, reason: "App 进入后台，局域网传输已停止")
    }

    // MARK: 服务回调

    private func refreshRecent() {
        recent = statusStore?.snapshot() ?? []
    }

    private func handleListenerFailure(_ message: String) {
        guard phase == .running || phase == .starting else { return }
        stop(notify: false)
        phase = .failed("监听中断：\(message)")
        toasts.show(.error, "局域网传输中断：\(message)")
    }

    // MARK: 导入

    private func handleUploadReady(_ ready: LanTransferUploadReady) {
        refreshRecent()

        guard autoImport else {
            statusStore?.setState(id: ready.id, state: .saved, reason: nil)
            return
        }

        pendingImports.append(
            PendingImport(id: ready.id, name: ready.name, destination: ready.destination)
        )
        scheduleImportFlush()
    }

    private func scheduleImportFlush() {
        guard !importFlushScheduled else { return }
        importFlushScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            await self?.flushImports()
        }
    }

    private func flushImports() async {
        importFlushScheduled = false
        guard !importing else { return }
        importing = true
        defer { importing = false }

        while !pendingImports.isEmpty {
            // 手动导入进行中：排队等它结束，避免 ShelfStore.importPaths 直接返回空
            while shelf.importing.active {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }

            guard autoImport else {
                for item in pendingImports {
                    statusStore?.setState(id: item.id, state: .saved, reason: nil)
                }
                pendingImports.removeAll()
                break
            }

            let batch = pendingImports
            pendingImports.removeAll()
            let results = await shelf.importPaths(batch.map(\.destination))
            applyImportResults(results, batch: batch)
        }
    }

    private func applyImportResults(_ results: [ImportResult], batch: [PendingImport]) {
        var byPath: [String: ImportResult] = [:]
        for result in results {
            byPath[Self.normalizedPath(result.path)] = result
        }

        for item in batch {
            guard let result = byPath[Self.normalizedPath(item.destination)] else {
                statusStore?.setState(id: item.id, state: .failed, reason: "导入未返回结果")
                continue
            }
            switch result.status {
            case .imported:
                statusStore?.setState(id: item.id, state: .imported, reason: nil)
            case .skipped:
                statusStore?.setState(id: item.id, state: .skipped, reason: result.reason)
            case .failed:
                statusStore?.setState(id: item.id, state: .failed, reason: result.reason)
            }
        }
        refreshRecent()
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
