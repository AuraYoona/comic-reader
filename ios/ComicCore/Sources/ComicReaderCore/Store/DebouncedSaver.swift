import Foundation

// MARK: - 防抖保存器（db.ts scheduleSave 的移植）
//
// 最早的截止时间生效：进度的长防抖不会推迟已排好的结构性写入
// （桌面版 SAVE_DEBOUNCE_MS = 400，PROGRESS_SAVE_DEBOUNCE_MS = 5000）。
//
// 锁序约定：调用方可能持有数据库锁再进入本对象（saveSoon/flushSync），
// 而写盘回调会反向申请数据库锁——因此本对象「绝不持锁调用写盘」：
// 先在队列内定好该不该写、清掉 dirty，释放队列后再回调。
// 时钟可注入，便于单元测试。

public protocol SaverTicket: AnyObject {
    func cancel()
}

public final class DebouncedSaver: @unchecked Sendable {
    public struct Clock: Sendable {
        public let now: @Sendable () -> Double
        public let schedule: @Sendable (@escaping @Sendable () -> Void, Double) -> SaverTicket

        public init(
            now: @escaping @Sendable () -> Double,
            schedule: @escaping @Sendable (@escaping @Sendable () -> Void, Double) -> SaverTicket
        ) {
            self.now = now
            self.schedule = schedule
        }
    }

    public enum Mode {
        case structural // 400ms
        case progress   // 5000ms
    }

    private let queue = DispatchQueue(label: "com.aurayoona.comicreader.saver")
    private var ticket: (any SaverTicket)?
    private var dueAt: Double = 0
    private var dirty = false
    /// 只在首次排程前通过 onFire 赋值一次；之后仅读不写
    nonisolated(unsafe) private var handler: (@Sendable () -> Void)?

    public let clock: Clock

    public init(clock: Clock) {
        self.clock = clock
    }

    /// 写盘回调（在排程前设置一次）
    public func onFire(_ h: @escaping @Sendable () -> Void) {
        queue.sync { handler = h }
    }

    public func saveSoon() { queue.sync { scheduleLocked(.structural) } }
    public func saveLazy() { queue.sync { scheduleLocked(.progress) } }

    private func scheduleLocked(_ mode: Mode) {
        dirty = true
        let delay: Double = mode == .structural ? 0.4 : 5.0
        let due = clock.now() + delay
        if let ticket {
            // 最早的截止时间生效：已排好的更早写入不被推迟
            if dueAt <= due { return }
            ticket.cancel()
        }
        dueAt = due
        let handler = self.handler
        ticket = clock.schedule({ [weak self] in
            guard let self else { return }
            // 队列内只决定「该不该写」，释放队列后再写，避免与数据库锁形成环
            let shouldWrite: Bool = self.queue.sync {
                self.ticket = nil
                let w = self.dirty
                self.dirty = false
                return w
            }
            if shouldWrite { handler?() }
        }, delay)
    }

    /// 应用退出 / 进入后台前同步写盘
    public func flushSync() {
        let shouldWrite: Bool = queue.sync {
            ticket?.cancel()
            ticket = nil
            let w = dirty
            dirty = false
            return w
        }
        if shouldWrite { handler?() }
    }
}

/// 生产时钟：DispatchSourceTimer（一次性触发）
final class DispatchSaverTicket: SaverTicket {
    let timer: DispatchSourceTimer
    init(timer: DispatchSourceTimer) { self.timer = timer }
    func cancel() { timer.cancel() }
}

extension DebouncedSaver.Clock {
    /// 定时器回调队列：不指定队列时 DispatchSource 默认派发到主队列，
    /// 写盘回调（整库 JSON 编码 + 落盘）会直接在主线程上执行
    private static let timerQueue = DispatchQueue(label: "com.aurayoona.comicreader.saver.timer")

    public static func live() -> DebouncedSaver.Clock {
        DebouncedSaver.Clock(
            now: { Date().timeIntervalSince1970 },
            schedule: { body, delay in
                let t = DispatchSource.makeTimerSource(queue: Self.timerQueue)
                t.schedule(deadline: .now() + delay)
                t.setEventHandler(handler: body)
                t.resume()
                return DispatchSaverTicket(timer: t)
            }
        )
    }
}
