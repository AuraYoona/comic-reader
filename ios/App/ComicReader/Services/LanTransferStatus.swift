import Foundation

// MARK: - 局域网传输状态仓库
//
// 写在 HTTP 连接线程、读在主线程（SwiftUI）与 HTTP 线程（/state 接口）。
// 用 NSLock 保护；onChange 在锁外触发，避免 UI 回调里再读快照造成死锁。

final class LanTransferStatusStore: @unchecked Sendable {
    enum State: String, Sendable {
        case receiving
        case importing
        case imported
        case skipped
        case failed
        case saved
    }

    struct Item: Identifiable, Equatable, Sendable {
        let id: String
        var name: String
        var size: Int64
        var received: Int64
        var state: State
        var reason: String?
    }

    /// 最多保留的最近记录数
    static let maxItems = 50

    /// 任意变更后的回调（在锁外、调用线程上执行）
    var onChange: (@Sendable () -> Void)?

    private let lock = NSLock()
    private var items: [Item] = []

    // MARK: 写入

    func begin(id: String, name: String, size: Int64) {
        mutate { items in
            items.insert(
                Item(id: id, name: name, size: size, received: 0, state: .receiving, reason: nil),
                at: 0
            )
            if items.count > Self.maxItems {
                items.removeLast(items.count - Self.maxItems)
            }
        }
    }

    func updateProgress(id: String, received: Int64) {
        mutate { items in
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            items[index].received = max(items[index].received, received)
            if items[index].size > 0 {
                items[index].received = min(items[index].received, items[index].size)
            }
        }
    }

    func finishReceiving(id: String, size: Int64, name: String?, state: State) {
        mutate { items in
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            if size > 0 { items[index].size = size }
            if let name, !name.isEmpty { items[index].name = name }
            items[index].received = items[index].size
            items[index].state = state
            items[index].reason = nil
        }
    }

    func setState(id: String, state: State, reason: String?) {
        mutate { items in
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            items[index].state = state
            items[index].reason = reason
        }
    }

    func fail(id: String, reason: String) {
        mutate { items in
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            items[index].state = .failed
            items[index].reason = reason
        }
    }

    /// 服务停止时：还没传完的标记失败；正在导入的保持不动（导入会继续）
    func failReceiving(reason: String) {
        mutate { items in
            for index in items.indices where items[index].state == .receiving {
                items[index].state = .failed
                items[index].reason = reason
            }
        }
    }

    func clear() {
        mutate { $0.removeAll() }
    }

    // MARK: 读取

    func snapshot() -> [Item] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }

    // MARK: 内部

    private func mutate(_ body: (inout [Item]) -> Void) {
        lock.lock()
        body(&items)
        let callback = onChange
        lock.unlock()
        callback?()
    }
}
