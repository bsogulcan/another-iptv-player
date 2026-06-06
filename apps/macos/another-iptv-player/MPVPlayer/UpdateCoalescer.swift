import Foundation

/// `mpv_render_context_set_update_callback` çok sık tetiklenebilir; her biri için `main.async`
/// ana kuyruğu tıkar. Bu sınıf aynı anda en fazla bir `main.async` blok planlar.
final class UpdateCoalescer {
  private let lock = NSLock()
  private var scheduled = false
  private let callback: () -> Void

  init(callback: @escaping () -> Void) {
    self.callback = callback
  }

  func schedule() {
    lock.lock()
    if scheduled {
      lock.unlock()
      return
    }
    scheduled = true
    lock.unlock()
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.lock.lock()
      self.scheduled = false
      self.lock.unlock()
      self.callback()
    }
  }
}
