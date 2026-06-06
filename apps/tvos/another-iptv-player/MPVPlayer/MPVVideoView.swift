import GLKit
import UIKit

final class MPVVideoView: GLKView {
    private weak var player: MPVPlayer?
    private var displayLink: CADisplayLink?

    init(player: MPVPlayer) {
        let context = EAGLContext(api: .openGLES3) ?? EAGLContext(api: .openGLES2)!
        self.player = player
        super.init(frame: .zero, context: context)

        drawableColorFormat = .RGBA8888
        drawableDepthFormat = .formatNone
        drawableStencilFormat = .formatNone
        enableSetNeedsDisplay = false
        isOpaque = true
        backgroundColor = .black

        // The simulator's OpenGL ES pipeline is software-rasterized; rendering
        // at 2× costs ~4× more CPU per frame. Stay at 1× on the simulator so
        // playback doesn't stall at single-digit FPS.
        #if targetEnvironment(simulator)
        contentScaleFactor = 1.0
        #else
        contentScaleFactor = UIScreen.main.scale
        #endif

        player.attach(glContext: context) { [weak self] in
            self?.requestRender()
        }

        let link = CADisplayLink(target: self, selector: #selector(tick))
        // A 25 fps stream only ever needs 30 ticks/s of headroom. Running the
        // display link at 60 on the simulator wastes main-thread time that the
        // GL present already needs.
        #if targetEnvironment(simulator)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
        #else
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        #endif
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        displayLink?.invalidate()
    }

    /// Stop the display link *synchronously* before the view leaves the hierarchy.
    /// Without this, `CADisplayLink(target: self, ...)` keeps `self` alive (retain
    /// cycle), so `deinit` never fires and `tick()` keeps running after the player
    /// has been disposed — which crashes inside `mpv_render_context_render`.
    func teardown() {
        displayLink?.invalidate()
        displayLink = nil
        player = nil
    }

    private var needsRender = false
    private func requestRender() {
        needsRender = true
    }

    @objc private func tick() {
        guard needsRender, let player else { return }
        needsRender = false

        if EAGLContext.current() !== context {
            EAGLContext.setCurrent(context)
        }
        bindDrawable()
        let w = Int32(drawableWidth)
        let h = Int32(drawableHeight)
        var fbo: GLint = 0
        glGetIntegerv(GLenum(GL_FRAMEBUFFER_BINDING), &fbo)
        player.drawGL(fbo: fbo, width: w, height: h)
        display()
    }
}
