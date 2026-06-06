import AVKit
import Combine
import CoreMedia
import SwiftUI
import UIKit

/// `AVSampleBufferDisplayLayer` + libmpv + Picture-in-Picture (sample buffer API, iOS 15+).
///
/// Mimari:
/// - `PixelBufferDisplayView` içindeki `AVSampleBufferDisplayLayer` hem inline render hem PiP
///   content source olarak kullanılır.
/// - PiP başlarken/kapanırken görünüm taşınmaz (eski video call API'deki reparenting çıktı);
///   sistem layer'ı doğrudan PiP penceresine kompoze eder. Inline görünümü `PlayerView`'deki
///   SwiftUI overlay ("Picture in Picture") örtüyor.
/// - Oynat/duraklat/skip PiP kontrolleri `AVPictureInPictureSampleBufferPlaybackDelegate`
///   üzerinden mpv'ye forward edilir.
final class MPVPlayerContainerViewController: UIViewController {
  private let mpvPlayer: MPVPlayer
  weak var playbackBridge: VideoPlayerController?

  private let displayView = PixelBufferDisplayView()
  private var pipController: AVPictureInPictureController?
  private var didConfigureMpv = false
  private var appLifecycleObservers: [NSObjectProtocol] = []
  private var controlTimebase: CMTimebase?
  private var currentVideoContentMode: UIView.ContentMode = .scaleAspectFit
  private var cancellables = Set<AnyCancellable>()

  /// PiP skip delegesinin son tetiklendiği an. iOS PiP bazı sürümlerde skip'ten hemen sonra
  /// spurious `setPlaying(false)` gönderiyor → mpv duraklıyor, kullanıcı manuel oynat tuşuna
  /// basmak zorunda kalıyor. Bu pencerede gelen `setPlaying(false)` olayları yutulur.
  private var lastSkipAt: Date?
  private let skipSuppressPlayingFalseWindow: TimeInterval = 0.6

  /// SwiftUI'den manuel PiP tetiklemek için artan sayaç.
  var lastProcessedManualPiPTrigger: Int = 0

  init(mpvPlayer: MPVPlayer, playbackBridge: VideoPlayerController?) {
    self.mpvPlayer = mpvPlayer
    self.playbackBridge = playbackBridge
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    for o in appLifecycleObservers {
      NotificationCenter.default.removeObserver(o)
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    edgesForExtendedLayout = .all

    // Autoresizing mask: layout passı olmadan container değişimlerini takip eder.
    displayView.translatesAutoresizingMaskIntoConstraints = true
    displayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    displayView.frame = view.bounds
    view.addSubview(displayView)

    configureMpvIfNeeded()
    displayView.setVideoContentMode(currentVideoContentMode)
    setupControlTimebase()
    setupPiP()
    setupBackgroundPauseFallback()
    observeMpvPlaybackState()
  }

  /// `AVSampleBufferDisplayLayer.controlTimebase` yoksa `AVPictureInPictureController` sample
  /// buffer modunda playback zamanını çıkaramaz; sistem `timeRangeForPlayback`'i sürekli
  /// yeniden sorgular ve PiP penceresini tekrar kurmaya çalışır (iPad'te "PiP kaybolup geliyor"
  /// davranışı). Host clock kaynaklı bir timebase vererek sistemin timing sorgularını stabil
  /// biçimde karşılarız; frame timing'i hâlâ `DisplayImmediately` ile bypass'lanıyor, bu yüzden
  /// timebase sadece PiP UI zamanını sürmek için kullanılır.
  private func setupControlTimebase() {
    guard controlTimebase == nil else { return }
    var tb: CMTimebase?
    let status = CMTimebaseCreateWithSourceClock(
      allocator: kCFAllocatorDefault,
      sourceClock: CMClockGetHostTimeClock(),
      timebaseOut: &tb
    )
    guard status == noErr, let tb else { return }
    CMTimebaseSetTime(tb, time: .zero)
    CMTimebaseSetRate(tb, rate: 0)
    displayView.sampleBufferDisplayLayer.controlTimebase = tb
    controlTimebase = tb
  }

  private func updateControlTimebase() {
    guard let tb = controlTimebase else { return }
    let pos = mpvPlayer.position
    if pos.isFinite, pos >= 0 {
      CMTimebaseSetTime(tb, time: CMTime(seconds: pos, preferredTimescale: 600))
    }
    CMTimebaseSetRate(tb, rate: mpvPlayer.isPaused ? 0 : 1)
  }

  func setVideoContentMode(_ mode: UIView.ContentMode) {
    currentVideoContentMode = mode
    if isViewLoaded {
      displayView.setVideoContentMode(mode)
    }
  }

  private func configureMpvIfNeeded() {
    guard !didConfigureMpv else { return }
    didConfigureMpv = true
    mpvPlayer.configure(
      enableHardwareAcceleration: true,
      onVideoSizeChange: { _ in },
      onFrame: { [weak self] buffer, _, flip in
        self?.displayView.enqueuePixelBuffer(buffer, flipVerticalForOpenGL: flip)
      }
    )
  }

  private func setupPiP() {
    guard pipEnabled else { return }
    guard pipController == nil else { return }
    guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
    let source = AVPictureInPictureController.ContentSource(
      sampleBufferDisplayLayer: displayView.sampleBufferDisplayLayer,
      playbackDelegate: self
    )
    let pip = AVPictureInPictureController(contentSource: source)
    pip.delegate = self
    // Apple'ın önerdiği arka plan PiP yolu: sistem willResignActive anında, layer görünür ve
    // timebase rate > 0 iken otomatik olarak PiP açar. Manuel `willResignActive` scheduling'i
    // yarış koşullarına açık (iPhone yatay + hızlı swipe-up'ta PiP atlanıyordu).
    pip.canStartPictureInPictureAutomaticallyFromInline = pipEnabled && continuePlayingInBackground
    pipController = pip
  }

  private func refreshAutomaticPiPFlag() {
    pipController?.canStartPictureInPictureAutomaticallyFromInline =
      pipEnabled && continuePlayingInBackground
  }

  /// mpv oynatma durumu değişince PiP üst çubuğundaki play/pause ikonu ve zaman aralığı
  /// güncellensin diye sistem state'i invalide edilir.
  ///
  /// Aynı zamanda VOD ilk açılışta mpv duration'ı henüz okumadan PiP'in `timeRangeForPlayback`'i
  /// sorgulamasının önüne geçer: duration 0 iken canlı aralık döndürüyoruz → duration gelince
  /// invalidate → sistem yeniden sorgular → doğru VOD aralığı (pause butonu).
  private func observeMpvPlaybackState() {
    mpvPlayer.$isPaused
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updateControlTimebase()
        self?.pipController?.invalidatePlaybackState()
      }
      .store(in: &cancellables)

    mpvPlayer.$duration
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.pipController?.invalidatePlaybackState()
      }
      .store(in: &cancellables)

    mpvPlayer.$isPlaybackEstablished
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updateControlTimebase()
        self?.pipController?.invalidatePlaybackState()
      }
      .store(in: &cancellables)
  }

  /// Arka plana alındığında PiP kapalıysa veya kullanıcı arka planda oynatmayı istemiyorsa
  /// mpv'yi duraklat. PiP başlatma işi artık sistemin otomatik PiP yoluna bırakıldı:
  /// `canStartPictureInPictureAutomaticallyFromInline = true`.
  private func setupBackgroundPauseFallback() {
    let obs = NotificationCenter.default.addObserver(
      forName: UIApplication.willResignActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.handleWillResignActive()
    }
    appLifecycleObservers = [obs]
  }

  var pipEnabled: Bool = true {
    didSet {
      guard oldValue != pipEnabled else { return }
      if pipEnabled {
        setupPiP()
      } else {
        pipController?.stopPictureInPicture()
        pipController = nil
      }
      refreshAutomaticPiPFlag()
    }
  }
  var continuePlayingInBackground: Bool = true {
    didSet {
      guard oldValue != continuePlayingInBackground else { return }
      refreshAutomaticPiPFlag()
    }
  }

  private func handleWillResignActive() {
    guard continuePlayingInBackground else {
      mpvPlayer.pause()
      return
    }
    // `continuePlayingInBackground == true` durumda sistemin otomatik PiP'i devreye girer
    // (layer görünür + timebase rate > 0). Ek bir manuel `startPictureInPicture` çağrısı
    // sistemin state makinesiyle çakışıp "PiP açılıp kapanıyor" davranışına yol açıyordu.
  }

  func processManualPiPTrigger(_ value: Int) {
    guard value != lastProcessedManualPiPTrigger else { return }
    lastProcessedManualPiPTrigger = value
    startPiPIfPossible()
  }

  func startPiPIfPossible() {
    guard let pip = pipController,
          pip.isPictureInPicturePossible,
          !pip.isPictureInPictureActive
    else { return }
    guard isActivelyPlayingForPiP else { return }
    pip.startPictureInPicture()
  }

  /// PiP başlatma için minimum kontrol: mpv hazır ve en az bir frame gelmiş olsun.
  private var isActivelyPlayingForPiP: Bool {
    mpvPlayer.isReady && mpvPlayer.isPlaybackEstablished
  }
}

// MARK: - AVPictureInPictureControllerDelegate

extension MPVPlayerContainerViewController: AVPictureInPictureControllerDelegate {
  func pictureInPictureControllerWillStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    // Sample buffer content source: reparent yok. Inline overlay placeholder didStart'ta yansıtılır.
  }

  func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    playbackBridge?.isPiPActive = true
  }

  func pictureInPictureControllerWillStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    // nothing
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    playbackBridge?.isPiPActive = false
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    playbackBridge?.isPiPActive = false
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    completionHandler(true)
  }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

extension MPVPlayerContainerViewController: AVPictureInPictureSampleBufferPlaybackDelegate {
  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    setPlaying playing: Bool
  ) {
    if playing {
      mpvPlayer.play()
    } else {
      if let last = lastSkipAt,
         Date().timeIntervalSince(last) < skipSuppressPlayingFalseWindow {
        // Skip sonrası iOS PiP'in kendiliğinden gönderdiği "pause" emitini yoksay;
        // aksi halde video duruyor ve kullanıcı manuel oynat tuşuna basmak zorunda kalıyor.
        return
      }
      mpvPlayer.pause()
    }
  }

  func pictureInPictureControllerTimeRangeForPlayback(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> CMTimeRange {
    // Canlı yayında skip kontrollerini gizlemek için öncelikli olarak bridge bayrağını oku;
    // mpv `duration` bazı canlı kaynaklarda pozitif dönebiliyor (EPG / cache süresi).
    if playbackBridge?.isLiveStream == true {
      return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }
    let durationSec = mpvPlayer.duration
    if durationSec > 0, durationSec.isFinite {
      let start = CMTime(value: 0, timescale: 600)
      let duration = CMTime(seconds: durationSec, preferredTimescale: 600)
      return CMTimeRange(start: start, duration: duration)
    }
    // Süre henüz bilinmiyor: sonsuz aralık ver; duration gelince observer invalidate eder.
    return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
  }

  func pictureInPictureControllerIsPlaybackPaused(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> Bool {
    mpvPlayer.isPaused
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    didTransitionToRenderSize newRenderSize: CMVideoDimensions
  ) {
    // Layer otomatik yeniden boyutlanır; özel işlem gerekmez.
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    skipByInterval skipInterval: CMTime,
    completion completionHandler: @escaping () -> Void
  ) {
    // Control Center ve merkez transport butonlarıyla aynı yolu kullan: `jump(seconds:)`
    // `markSeekRequestStart()` üzerinden UI state'ini (scrub / loading) senkronize tutar;
    // doğrudan `mpvPlayer.seek` çağırmak bazı kaynaklarda boşa çıkıyordu.
    let seconds = Int(CMTimeGetSeconds(skipInterval).rounded())
    let wasPlayingBeforeSkip = !mpvPlayer.isPaused
    lastSkipAt = Date()

    if let bridge = playbackBridge {
      bridge.jump(seconds: seconds)
    } else {
      let target = mpvPlayer.position + Double(seconds)
      mpvPlayer.seek(to: max(0, target))
    }

    // PiP UI'ındaki zaman göstergesini yeni pozisyona ani olarak kaydır; mpv seek tamamlanınca
    // `$isPlaybackEstablished` observer'ı timebase'i kesin mpv.position ile yeniden senkronlar.
    if let tb = controlTimebase {
      let estimatedTarget = max(0, mpvPlayer.position + Double(seconds))
      CMTimebaseSetTime(tb, time: CMTime(seconds: estimatedTarget, preferredTimescale: 600))
    }

    // Belt-and-suspenders: skip öncesinde oynuyorsa, seek'in tamamlanmasının ardından
    // mpv'yi oynatmaya zorla. iOS PiP spurious `setPlaying(false)` olaylarından bağımsız olarak
    // ikinci bir garanti sağlar.
    if wasPlayingBeforeSkip {
      DispatchQueue.main.async { [weak self] in
        self?.mpvPlayer.play()
      }
    }

    completionHandler()
  }
}

/// `PlayerView` ve demo için: video yüzeyi + PiP.
struct MPVPlayerPlaybackContainerView: UIViewControllerRepresentable {
  @ObservedObject var mpvPlayer: MPVPlayer
  var playbackBridge: VideoPlayerController?
  var manualPiPTrigger: Int
  var pipEnabled: Bool
  var continuePlayingInBackground: Bool

  func makeUIViewController(context: Context) -> MPVPlayerContainerViewController {
    let vc = MPVPlayerContainerViewController(mpvPlayer: mpvPlayer, playbackBridge: playbackBridge)
    vc.lastProcessedManualPiPTrigger = manualPiPTrigger
    vc.pipEnabled = pipEnabled
    vc.continuePlayingInBackground = continuePlayingInBackground
    vc.setVideoContentMode(playbackBridge?.aspectMode.viewportContentMode ?? .scaleAspectFit)
    return vc
  }

  func updateUIViewController(_ uiViewController: MPVPlayerContainerViewController, context: Context) {
    uiViewController.playbackBridge = playbackBridge
    uiViewController.pipEnabled = pipEnabled
    uiViewController.continuePlayingInBackground = continuePlayingInBackground
    uiViewController.setVideoContentMode(playbackBridge?.aspectMode.viewportContentMode ?? .scaleAspectFit)
    uiViewController.processManualPiPTrigger(manualPiPTrigger)
  }
}
