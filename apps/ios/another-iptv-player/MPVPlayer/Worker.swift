// Same threading model as MPVPlayer `Worker.swift` (dedicated serial thread + semaphore).
// https://stackoverflow.com/questions/49043257/how-to-ensure-to-run-some-code-on-same-background-thread/49075382#49075382

import Foundation

final class Worker {
  typealias Job = () -> Void

  private let semaphore = DispatchSemaphore(value: 0)
  private let lock = NSRecursiveLock()
  private var thread: Thread!
  private var queue = [Job]()
  private var canceled = false

  init() {
    thread = Thread(block: loop)
    thread.start()
  }

  func cancel() {
    signalCancel()
    thread.cancel()
  }

  func enqueue(_ job: @escaping Job) {
    locked {
      queue.append(job)
    }
    semaphore.signal()
  }

  private func loop() {
    while true {
      semaphore.wait()
      if isCanceled() { return }
      let job = getFirstJob()
      job()
    }
  }

  private func signalCancel() {
    locked { canceled = true }
    semaphore.signal()
  }

  private func isCanceled() -> Bool {
    locked { canceled }
  }

  private func getFirstJob() -> Job {
    locked { queue.removeFirst() }
  }

  private func locked<T>(do block: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return block()
  }
}
