import Foundation

/// Keep notification-center mutations ordered even when authorization or add() suspends.
@MainActor
final class ReminderWorkQueue {
    private var tail: Task<Void, Never>?
    @discardableResult
    func enqueue(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let preceding = tail
        let task = Task { @MainActor in
            await preceding?.value
            await operation()
        }
        tail = task
        return task
    }
}
