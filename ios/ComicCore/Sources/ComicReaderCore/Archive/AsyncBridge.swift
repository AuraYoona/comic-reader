import Foundation

// MARK: - 同步适配桥
//
// ArchiveReader 协议刻意设计为同步（对应桌面版里主进程 handler 的 await 点都在
// 调用方控制）。HandleCache 内部是 async；这里把 acquire 桥回同步世界。
// 阅读器每页一次调用，阻塞等待一次文件打开的开销可接受；
// 真正的并发合并语义仍然保留在 HandleCache 内部。

enum AsyncBridgeError: Error { case timedOut }

func awaitBlocking<T: Sendable>(
    timeout: TimeInterval = 30,
    _ body: @escaping @Sendable () async throws -> T
) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: Result<T, Error>?
    let box = ResultBox()
    let task = Task<Void, Never> {
        do {
            box.store(try await body())
        } catch {
            box.storeError(error)
        }
        semaphore.signal()
    }
    defer { task.cancel() }
    guard semaphore.wait(timeout: .now() + timeout) == .success else {
        throw AsyncBridgeError.timedOut
    }
    return try box.take()
}

/// 线程安全的单值结果容器（绕过 Swift 并发的 exclusive-access 检查）
final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Any?

    func store<T>(_ v: T) {
        lock.lock(); value = Result<T, Error>.success(v) as Any; lock.unlock()
    }

    func storeError(_ e: Error) {
        lock.lock(); value = Result<Never, Error>.failure(e) as Any; lock.unlock()
    }

    func take<T>() throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard let r = value as? Result<T, Error> else { throw AsyncBridgeError.timedOut }
        return try r.get()
    }
}
