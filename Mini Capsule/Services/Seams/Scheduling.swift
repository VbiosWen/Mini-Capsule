import Foundation

protocol Cancellable: AnyObject { func cancel() }

/// Timer/dispatch abstraction so burst/poll timing is deterministic in tests.
protocol Scheduling: AnyObject {
    @discardableResult func after(_ delay: TimeInterval, _ block: @escaping () -> Void) -> Cancellable
    @discardableResult func every(_ interval: TimeInterval, _ block: @escaping () -> Void) -> Cancellable
}

final class RealScheduler: Scheduling {
    private final class TimerToken: Cancellable {
        let timer: Timer
        init(_ timer: Timer) { self.timer = timer }
        func cancel() { timer.invalidate() }
    }
    private final class WorkToken: Cancellable {
        let item: DispatchWorkItem
        init(_ item: DispatchWorkItem) { self.item = item }
        func cancel() { item.cancel() }
    }

    @discardableResult func after(_ delay: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
        let item = DispatchWorkItem(block: block)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return WorkToken(item)
    }

    @discardableResult func every(_ interval: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in block() }
        return TimerToken(timer)
    }
}
