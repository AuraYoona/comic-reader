import XCTest
@testable import ComicReaderCore

// DebouncedSaver 的「最早截止时间生效」语义（对照 db.ts scheduleSave）

/// 可手动推进的测试时钟
final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var now: Double = 0
    private var entries: [(id: Int, dueAt: Double, body: @Sendable () -> Void, ticket: TestTicket)] = []
    private var nextId = 0

    final class TestTicket: SaverTicket, @unchecked Sendable {
        private let lock = NSLock()
        private var _cancelled = false
        func cancel() { lock.lock(); _cancelled = true; lock.unlock() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelled }
    }

    var clock: DebouncedSaver.Clock {
        DebouncedSaver.Clock(
            now: { [weak self] in
                guard let self else { return 0 }
                self.lock.lock(); defer { self.lock.unlock() }
                return self.now
            },
            schedule: { [weak self] body, delay in
                guard let self else { return TestTicket() }
                self.lock.lock(); defer { self.lock.unlock() }
                let ticket = TestTicket()
                self.entries.append((self.nextId, self.now + delay, body, ticket))
                self.nextId += 1
                return ticket
            }
        )
    }

    var currentTime: Double {
        lock.lock(); defer { lock.unlock() }
        return now
    }

    /// 把时间推进 delta 秒，并按到期顺序触发到期的（未取消的）回调
    func advance(by delta: Double) {
        lock.lock()
        now += delta
        let due = entries.filter { $0.dueAt <= now && !$0.ticket.isCancelled }.sorted { $0.dueAt < $1.dueAt }
        entries.removeAll { $0.dueAt <= now }
        lock.unlock()
        for e in due { e.body() }
    }
}

/// 线程安全计数器（@Sendable 闭包不能捕获可变局部变量）
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

final class DebouncedSaverTests: XCTestCase {
    func testStructuralWriteFiresAfter400ms() {
        let manual = ManualClock()
        let fires = Counter()
        let saver = DebouncedSaver(clock: manual.clock)
        saver.onFire { fires.increment() }

        saver.saveSoon()
        manual.advance(by: 0.39)
        XCTAssertEqual(fires.count, 0)
        manual.advance(by: 0.02)
        XCTAssertEqual(fires.count, 1)
    }

    func testProgressSaveWaitsFiveSeconds() {
        let manual = ManualClock()
        let fires = Counter()
        let saver = DebouncedSaver(clock: manual.clock)
        saver.onFire { fires.increment() }

        saver.saveLazy()
        manual.advance(by: 4.9)
        XCTAssertEqual(fires.count, 0)
        manual.advance(by: 0.2)
        XCTAssertEqual(fires.count, 1)
    }

    func testEarliestDeadlineWins() {
        let manual = ManualClock()
        let fires = Counter()
        let saver = DebouncedSaver(clock: manual.clock)
        saver.onFire { fires.increment() }

        saver.saveSoon()   // 到期 0.4s
        saver.saveLazy()   // 5s：不得推迟已排好的 0.4s 写入
        manual.advance(by: 0.41)
        XCTAssertEqual(fires.count, 1, "结构性写入应按时触发，且一次写入即包含全部改动")

        // 0.4s 那次写入后 dirty 已清；不再有后续触发
        manual.advance(by: 5)
        XCTAssertEqual(fires.count, 1)
    }

    func testLaterStructuralReschedulesEarlier() {
        let manual = ManualClock()
        let fires = Counter()
        let saver = DebouncedSaver(clock: manual.clock)
        saver.onFire { fires.increment() }

        saver.saveLazy()   // 到期 5s
        saver.saveSoon()   // 到期 0.4s：更早，重排
        manual.advance(by: 0.41)
        XCTAssertEqual(fires.count, 1)
    }

    func testConsecutiveStructuralKeepsEarliest() {
        let manual = ManualClock()
        let fires = Counter()
        let saver = DebouncedSaver(clock: manual.clock)
        saver.onFire { fires.increment() }

        saver.saveSoon()
        manual.advance(by: 0.2)
        saver.saveSoon() // 新到期 0.6s；已排的 0.4s 更早，保持不动
        manual.advance(by: 0.21) // t=0.41
        XCTAssertEqual(fires.count, 1, "应保留最早的 0.4s 截止时间")
    }

    func testFlushSyncWritesImmediately() {
        let manual = ManualClock()
        let fires = Counter()
        let saver = DebouncedSaver(clock: manual.clock)
        saver.onFire { fires.increment() }

        saver.saveSoon()
        saver.flushSync()
        XCTAssertEqual(fires.count, 1)
        // 已排的定时器被取消，后续推进不再触发
        manual.advance(by: 10)
        XCTAssertEqual(fires.count, 1)
    }

    func testFlushWithoutPendingWriteDoesNothing() {
        let manual = ManualClock()
        let fires = Counter()
        let saver = DebouncedSaver(clock: manual.clock)
        saver.onFire { fires.increment() }

        saver.flushSync()
        XCTAssertEqual(fires.count, 0)
    }
}
