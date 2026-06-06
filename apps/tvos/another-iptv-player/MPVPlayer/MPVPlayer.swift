import Combine
import Foundation
import GLKit
import QuartzCore

public struct MPVTrack: Identifiable, Hashable {
    public enum Kind: String {
        case video, audio, sub
    }

    public let id: Int64
    public let kind: Kind
    public let title: String?
    public let lang: String?
    public let codec: String?

    public var displayName: String {
        let base: String
        if let title, !title.isEmpty { base = title }
        else if let lang, !lang.isEmpty { base = lang.uppercased() }
        else { base = "Track \(id)" }
        if let codec, !codec.isEmpty, title == nil || title?.isEmpty == true {
            return "\(base) · \(codec)"
        }
        return base
    }
}

public final class MPVPlayer: ObservableObject {
    private static let wakeupCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { userdata in
        guard let userdata else { return }
        Unmanaged<MPVPlayer>.fromOpaque(userdata).takeUnretainedValue().drainEvents()
    }

    private static let updateCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { userdata in
        guard let userdata else { return }
        Unmanaged<MPVPlayer>.fromOpaque(userdata).takeUnretainedValue().onUpdateRequested()
    }

    private static let glFrameworkHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES", RTLD_NOW)
    }()

    private static let getProcAddress: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<Int8>?) -> UnsafeMutableRawPointer? = { _, name in
        guard let name else { return nil }
        if let handle = MPVPlayer.glFrameworkHandle,
           let sym = dlsym(handle, name) {
            return sym
        }
        return dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
    }

    private let queue = DispatchQueue(label: "MPVPlayer.mpv", qos: .userInitiated)
    private var mpv: OpaquePointer?
    private var renderCtx: OpaquePointer?
    private var retained: Unmanaged<MPVPlayer>?
    private var isDisposed = false
    private var glContext: EAGLContext?
    private var wantsRedraw: (() -> Void)?

    @Published public private(set) var isPaused = true
    @Published public private(set) var position: TimeInterval = 0
    @Published public private(set) var duration: TimeInterval = 0
    @Published public private(set) var mediaTitle: String = ""
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var deliveredFPS: Double = 0
    @Published public private(set) var streamFPS: Double = 0
    @Published public private(set) var droppedFrameCount: Int64 = 0
    @Published public private(set) var delayedFrameCount: Int64 = 0
    @Published public private(set) var videoCodec: String = ""
    @Published public private(set) var hwdecCurrent: String = ""
    @Published public private(set) var videoWidth: Int = 0
    @Published public private(set) var videoHeight: Int = 0
    @Published public private(set) var videoTracks: [MPVTrack] = []
    @Published public private(set) var audioTracks: [MPVTrack] = []
    @Published public private(set) var subtitleTracks: [MPVTrack] = []
    @Published public private(set) var selectedVideoTrackID: Int64 = 0
    @Published public private(set) var selectedAudioTrackID: Int64 = 0
    @Published public private(set) var selectedSubtitleTrackID: Int64 = 0

    private var fpsWindowStart: CFTimeInterval = 0
    private var fpsWindowCount: Int = 0
    private var lastPositionPublishAt: CFTimeInterval = 0

    public init() {}

    deinit {
        disposeSync()
    }

    /// Called by MPVGLView once its GL context is ready. `wantsRedraw` is invoked
    /// from mpv's render-update callback; the view uses it to schedule `display()`.
    /// Must be called on the main thread — GL context needs to be "current" here
    /// for `mpv_render_context_create` to query the GL state successfully.
    public func attach(glContext: EAGLContext, wantsRedraw: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        self.glContext = glContext
        self.wantsRedraw = wantsRedraw

        let previous = EAGLContext.current()
        EAGLContext.setCurrent(glContext)
        defer { EAGLContext.setCurrent(previous) }

        if mpv == nil { bootstrap() }
        if renderCtx == nil { createRenderContext() }
    }

    /// Loads a URL and optionally starts playback at a specific position.
    /// Using mpv's `start=<sec>` loadfile option is atomic: the demuxer seeks
    /// before the first frame is decoded, so there is no visible jump and no
    /// race with `duration` being published.
    public func load(_ url: URL, startAt seconds: TimeInterval = 0) {
        NSLog("MPVPlayer: loading %@ startAt=%f", url.absoluteString, seconds)
        queue.async { [weak self] in
            guard let self, let handle = self.mpv, !self.isDisposed else { return }
            // mpv 0.36 loadfile syntax: <url> [<flags> [<options>]].
            // (The <index> slot between flags and options was only added in
            // 0.37 — passing it here would make mpv reject the command.)
            var tokens = ["loadfile", url.absoluteString, "replace"]
            if seconds > 1.0 {
                tokens.append("start=\(seconds)")
            }
            let cStrings: [UnsafeMutablePointer<CChar>?] = tokens.map { strdup($0) }
            defer { cStrings.forEach { if let p = $0 { free(p) } } }
            var argv: [UnsafePointer<CChar>?] = cStrings.map { UnsafePointer($0) }
            argv.append(nil)
            _ = mpv_command(handle, &argv)
            var flag: CInt = 0
            _ = mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &flag)
        }
    }

    public func play()  { setPaused(false) }
    public func pause() { setPaused(true) }

    public func togglePause() {
        queue.async { [weak self] in
            guard let self, let handle = self.mpv, !self.isDisposed else { return }
            var current: CInt = 0
            _ = mpv_get_property(handle, "pause", MPV_FORMAT_FLAG, &current)
            var flipped: CInt = current == 0 ? 1 : 0
            _ = mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &flipped)
        }
    }

    public func seek(to seconds: TimeInterval) {
        queue.async { [weak self] in
            guard let self, let handle = self.mpv, !self.isDisposed else { return }
            let cmd = "seek \(seconds) absolute"
            cmd.withCString { _ = mpv_command_string(handle, $0) }
        }
    }

    public func seekRelative(_ offset: TimeInterval) {
        queue.async { [weak self] in
            guard let self, let handle = self.mpv, !self.isDisposed else { return }
            let cmd = "seek \(offset) relative+exact"
            cmd.withCString { _ = mpv_command_string(handle, $0) }
        }
    }

    public func selectTrack(kind: MPVTrack.Kind, id: Int64) {
        let propName: String
        switch kind {
        case .video: propName = "vid"
        case .audio: propName = "aid"
        case .sub:   propName = "sid"
        }
        queue.async { [weak self] in
            guard let self, let handle = self.mpv, !self.isDisposed else { return }
            if id <= 0 {
                "no".withCString { val in
                    _ = mpv_set_property_string(handle, propName, val)
                }
            } else {
                let str = String(id)
                str.withCString { val in
                    _ = mpv_set_property_string(handle, propName, val)
                }
            }
        }
    }

    public func dispose() {
        queue.async { [weak self] in
            self?.disposeSync()
        }
    }

    /// Called from the GLKView on its GL thread. `fbo` is the bound framebuffer.
    public func drawGL(fbo: GLint, width: Int32, height: Int32) {
        guard let ctx = renderCtx else { return }

        var fboParam = mpv_opengl_fbo(fbo: CInt(fbo), w: CInt(width), h: CInt(height), internal_format: 0)
        var flipY: CInt = 1

        var params: [mpv_render_param] = [
            mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: &fboParam),
            mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: &flipY),
            mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
        ]
        _ = params.withUnsafeMutableBufferPointer { buf in
            mpv_render_context_render(ctx, buf.baseAddress)
        }
        _ = mpv_render_context_report_swap(ctx)

        let now = CACurrentMediaTime()
        if fpsWindowStart == 0 { fpsWindowStart = now }
        fpsWindowCount += 1
        let elapsed = now - fpsWindowStart
        if elapsed >= 1.0 {
            let fps = Double(fpsWindowCount) / elapsed
            fpsWindowStart = now
            fpsWindowCount = 0
            DispatchQueue.main.async { [weak self] in self?.deliveredFPS = fps }
        }
    }

    // MARK: - Private

    private func bootstrap() {
        guard let handle = mpv_create() else {
            postError("mpv_create failed")
            return
        }

        _ = mpv_set_option_string(handle, "vo", "libmpv")
        #if targetEnvironment(simulator)
        _ = mpv_set_option_string(handle, "hwdec", "no")
        #else
        _ = mpv_set_option_string(handle, "hwdec", "videotoolbox")
        #endif
        _ = mpv_set_option_string(handle, "keep-open", "yes")
        _ = mpv_set_option_string(handle, "idle", "yes")
        _ = mpv_set_option_string(handle, "audio-display", "no")
        _ = mpv_set_option_string(handle, "cache", "yes")
        _ = mpv_set_option_string(handle, "network-timeout", "14")
        _ = mpv_set_option_string(handle, "video-sync", "audio")
        _ = mpv_set_option_string(handle, "interpolation", "no")
        _ = mpv_set_option_string(handle, "scale", "bilinear")
        _ = mpv_set_option_string(handle, "dscale", "bilinear")
        _ = mpv_set_option_string(handle, "hwdec-codecs", "all")
        // We render our own controls + scrubber overlay. Silence mpv's built-in
        // OSD entirely so the seek/pause text doesn't flash on top of ours.
        _ = mpv_set_option_string(handle, "osd-level", "0")
        _ = mpv_set_option_string(handle, "osd-on-seek", "no")
        _ = mpv_set_option_string(handle, "osc", "no")

        let st = mpv_initialize(handle)
        if st < 0 {
            postError("mpv_initialize: \(String(cString: mpv_error_string(st)))")
            return
        }

        mpv = handle
        retained = Unmanaged.passRetained(self)
        mpv_set_wakeup_callback(handle, Self.wakeupCallback, retained!.toOpaque())
        _ = mpv_request_log_messages(handle, "info")
        observeProperties(handle: handle)
        createRenderContext()
    }

    private func createRenderContext() {
        guard let handle = mpv, glContext != nil, renderCtx == nil else { return }

        var apiType = strdup(MPV_RENDER_API_TYPE_OPENGL)!
        defer { free(apiType) }

        var gl = mpv_opengl_init_params(
            get_proc_address: Self.getProcAddress,
            get_proc_address_ctx: nil
        )
        var advanced: CInt = 1
        var params: [mpv_render_param] = [
            mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiType),
            mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: &gl),
            mpv_render_param(type: MPV_RENDER_PARAM_ADVANCED_CONTROL, data: &advanced),
            mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
        ]

        var ctx: OpaquePointer?
        let st = params.withUnsafeMutableBufferPointer { buf in
            mpv_render_context_create(&ctx, handle, buf.baseAddress)
        }
        if st < 0 {
            postError("render_context_create: \(String(cString: mpv_error_string(st)))")
            return
        }
        renderCtx = ctx

        if let ctx, let retained {
            mpv_render_context_set_update_callback(ctx, Self.updateCallback, retained.toOpaque())
        }
    }

    private func onUpdateRequested() {
        guard let ctx = renderCtx else { return }
        let flags = mpv_render_context_update(ctx)
        if (flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue)) != 0 {
            wantsRedraw?()
        }
    }

    private func setPaused(_ paused: Bool) {
        queue.async { [weak self] in
            guard let self, let handle = self.mpv, !self.isDisposed else { return }
            var flag: CInt = paused ? 1 : 0
            _ = mpv_set_property(handle, "pause", MPV_FORMAT_FLAG, &flag)
        }
    }

    private func observeProperties(handle: OpaquePointer) {
        let props: [(UInt64, String, mpv_format)] = [
            (1, "time-pos", MPV_FORMAT_DOUBLE),
            (2, "duration", MPV_FORMAT_DOUBLE),
            (3, "pause", MPV_FORMAT_FLAG),
            (4, "media-title", MPV_FORMAT_STRING),
            (5, "estimated-vf-fps", MPV_FORMAT_DOUBLE),
            (6, "container-fps", MPV_FORMAT_DOUBLE),
            (7, "vo-drop-frame-count", MPV_FORMAT_INT64),
            (8, "vo-delayed-frame-count", MPV_FORMAT_INT64),
            (9, "video-codec", MPV_FORMAT_STRING),
            (10, "hwdec-current", MPV_FORMAT_STRING),
            (11, "dwidth", MPV_FORMAT_INT64),
            (12, "dheight", MPV_FORMAT_INT64),
            (13, "track-list/count", MPV_FORMAT_INT64),
            (14, "vid", MPV_FORMAT_INT64),
            (15, "aid", MPV_FORMAT_INT64),
            (16, "sid", MPV_FORMAT_INT64),
        ]
        for (rid, name, fmt) in props {
            _ = mpv_observe_property(handle, rid, name, fmt)
        }
    }

    private func drainEvents() {
        queue.async { [weak self] in
            guard let self, let handle = self.mpv, !self.isDisposed else { return }
            while true {
                guard let evPtr = mpv_wait_event(handle, 0) else { break }
                let ev = evPtr.pointee
                if ev.event_id == MPV_EVENT_NONE { break }
                self.handleEvent(ev)
            }
        }
    }

    private func handleEvent(_ ev: mpv_event) {
        guard let handle = mpv else { return }
        switch ev.event_id {
        case MPV_EVENT_PROPERTY_CHANGE:
            publishProperty(handle: handle, replyId: ev.reply_userdata)
        case MPV_EVENT_LOG_MESSAGE:
            if let data = ev.data {
                let msg = data.assumingMemoryBound(to: mpv_event_log_message.self).pointee
                let prefix = msg.prefix.map { String(cString: $0) } ?? ""
                let text = msg.text.map { String(cString: $0) } ?? ""
                NSLog("mpv[%@]: %@", prefix, text.trimmingCharacters(in: .newlines))
            }
        case MPV_EVENT_END_FILE:
            if let data = ev.data {
                let end = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                if end.reason == MPV_END_FILE_REASON_ERROR {
                    postError("playback ended: \(String(cString: mpv_error_string(end.error)))")
                }
            }
        default:
            break
        }
    }

    private func publishProperty(handle: OpaquePointer, replyId: UInt64) {
        switch replyId {
        case 1:
            var v: Double = 0
            _ = mpv_get_property(handle, "time-pos", MPV_FORMAT_DOUBLE, &v)
            // mpv emits time-pos every decoded frame (~25 Hz). SwiftUI rebuilds
            // PlayerView on each change, which starves the GL present. The UI
            // only needs ~4 Hz for the progress bar to look smooth.
            let now = CACurrentMediaTime()
            if now - lastPositionPublishAt < 0.25 { return }
            lastPositionPublishAt = now
            DispatchQueue.main.async { [weak self] in self?.position = v }
        case 2:
            var v: Double = 0
            _ = mpv_get_property(handle, "duration", MPV_FORMAT_DOUBLE, &v)
            DispatchQueue.main.async { [weak self] in self?.duration = v }
        case 3:
            var v: CInt = 0
            _ = mpv_get_property(handle, "pause", MPV_FORMAT_FLAG, &v)
            let paused = v != 0
            DispatchQueue.main.async { [weak self] in self?.isPaused = paused }
        case 4:
            let title = fetchString(handle, "media-title")
            DispatchQueue.main.async { [weak self] in self?.mediaTitle = title }
        case 5:
            var v: Double = 0
            _ = mpv_get_property(handle, "estimated-vf-fps", MPV_FORMAT_DOUBLE, &v)
            DispatchQueue.main.async { [weak self] in self?.streamFPS = v }
        case 6:
            var v: Double = 0
            _ = mpv_get_property(handle, "container-fps", MPV_FORMAT_DOUBLE, &v)
            DispatchQueue.main.async { [weak self] in
                if self?.streamFPS == 0 { self?.streamFPS = v }
            }
        case 7:
            var v: Int64 = 0
            _ = mpv_get_property(handle, "vo-drop-frame-count", MPV_FORMAT_INT64, &v)
            DispatchQueue.main.async { [weak self] in self?.droppedFrameCount = v }
        case 8:
            var v: Int64 = 0
            _ = mpv_get_property(handle, "vo-delayed-frame-count", MPV_FORMAT_INT64, &v)
            DispatchQueue.main.async { [weak self] in self?.delayedFrameCount = v }
        case 9:
            let codec = fetchString(handle, "video-codec")
            DispatchQueue.main.async { [weak self] in self?.videoCodec = codec }
        case 10:
            let hw = fetchString(handle, "hwdec-current")
            DispatchQueue.main.async { [weak self] in self?.hwdecCurrent = hw }
        case 11:
            var v: Int64 = 0
            _ = mpv_get_property(handle, "dwidth", MPV_FORMAT_INT64, &v)
            DispatchQueue.main.async { [weak self] in self?.videoWidth = Int(v) }
        case 12:
            var v: Int64 = 0
            _ = mpv_get_property(handle, "dheight", MPV_FORMAT_INT64, &v)
            DispatchQueue.main.async { [weak self] in self?.videoHeight = Int(v) }
        case 13:
            let (video, audio, sub) = fetchTracks(handle)
            DispatchQueue.main.async { [weak self] in
                self?.videoTracks = video
                self?.audioTracks = audio
                self?.subtitleTracks = sub
            }
        case 14:
            var v: Int64 = 0
            _ = mpv_get_property(handle, "vid", MPV_FORMAT_INT64, &v)
            DispatchQueue.main.async { [weak self] in self?.selectedVideoTrackID = v }
        case 15:
            var v: Int64 = 0
            _ = mpv_get_property(handle, "aid", MPV_FORMAT_INT64, &v)
            DispatchQueue.main.async { [weak self] in self?.selectedAudioTrackID = v }
        case 16:
            var v: Int64 = 0
            _ = mpv_get_property(handle, "sid", MPV_FORMAT_INT64, &v)
            DispatchQueue.main.async { [weak self] in self?.selectedSubtitleTrackID = v }
        default:
            break
        }
    }

    private func fetchTracks(_ handle: OpaquePointer) -> ([MPVTrack], [MPVTrack], [MPVTrack]) {
        var count: Int64 = 0
        _ = mpv_get_property(handle, "track-list/count", MPV_FORMAT_INT64, &count)
        var video: [MPVTrack] = []
        var audio: [MPVTrack] = []
        var sub: [MPVTrack] = []
        for i in 0..<Int(count) {
            let typeStr = fetchString(handle, "track-list/\(i)/type")
            guard let kind = MPVTrack.Kind(rawValue: typeStr) else { continue }
            var id: Int64 = 0
            _ = mpv_get_property(handle, "track-list/\(i)/id", MPV_FORMAT_INT64, &id)
            let title = fetchOptionalString(handle, "track-list/\(i)/title")
            let lang  = fetchOptionalString(handle, "track-list/\(i)/lang")
            let codec = fetchOptionalString(handle, "track-list/\(i)/codec")
            let track = MPVTrack(id: id, kind: kind, title: title, lang: lang, codec: codec)
            switch kind {
            case .video: video.append(track)
            case .audio: audio.append(track)
            case .sub:   sub.append(track)
            }
        }
        return (video, audio, sub)
    }

    private func fetchOptionalString(_ handle: OpaquePointer, _ name: String) -> String? {
        var cstr: UnsafeMutablePointer<CChar>?
        let st = mpv_get_property(handle, name, MPV_FORMAT_STRING, &cstr)
        defer { if let cstr { mpv_free(cstr) } }
        guard st >= 0, let cstr else { return nil }
        let out = String(cString: cstr)
        return out.isEmpty ? nil : out
    }

    private func fetchString(_ handle: OpaquePointer, _ name: String) -> String {
        var cstr: UnsafeMutablePointer<CChar>?
        _ = mpv_get_property(handle, name, MPV_FORMAT_STRING, &cstr)
        let out = cstr.map { String(cString: $0) } ?? ""
        if let cstr { mpv_free(cstr) }
        return out
    }

    private func postError(_ msg: String) {
        NSLog("MPVPlayer: \(msg)")
        DispatchQueue.main.async { [weak self] in self?.errorMessage = msg }
    }

    private func disposeSync() {
        if isDisposed { return }
        isDisposed = true

        if let ctx = renderCtx {
            mpv_render_context_set_update_callback(ctx, nil, nil)
            mpv_render_context_free(ctx)
            renderCtx = nil
        }
        if let handle = mpv {
            mpv_set_wakeup_callback(handle, nil, nil)
            mpv_terminate_destroy(handle)
            mpv = nil
        }
        if let r = retained {
            r.release()
            retained = nil
        }
        glContext = nil
        wantsRedraw = nil
    }
}
