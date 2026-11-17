import Foundation

// Appending this to ReminderWorkQueue.swift tests an in-flight add followed by removal.
@MainActor
func runQueueChecks() async {
    let queue = ReminderWorkQueue()
    var log: [String] = []
    var resume: CheckedContinuation<Void, Never>?
    let add = queue.enqueue {
        log.append("add-start")
        await withCheckedContinuation { continuation in resume = continuation }
        log.append("add-complete")
    }
    while resume == nil { await Task.yield() }
    let remove = queue.enqueue { log.append("remove") }
    await Task.yield()
    precondition(log == ["add-start"], "Removal must not run ahead of an in-flight notification add")
    resume?.resume()
    await add.value
    await remove.value
    precondition(log == ["add-start", "add-complete", "remove"], "Cancelling after add must leave the reminder removed")
    print("PASS: queued removal waits for in-flight reminder installation")
    var version = 1
    var applied: [Int] = []
    let firstVersion = version
    let first = queue.enqueue {
        guard version == firstVersion else { return }
        applied.append(firstVersion)
    }
    version = 2
    let second = queue.enqueue {
        guard version == 2 else { return }
        applied.append(2)
    }
    await first.value; await second.value
    precondition(applied == [2], "Superseded settings must not be installed")
    print("PASS: superseded reminder settings are skipped")
}
await runQueueChecks()
