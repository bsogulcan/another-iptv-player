import AppKit
import AVFoundation
import CoreVideo
import Metal
import MetalKit
import QuartzCore

/// macOS native Metal display layer — CAMetalLayer arkalı NSView.
/// mpv'nin IOSurface-backed CVPixelBuffer çıkışını CVMetalTextureCache ile
/// MTLTexture'a zero-copy bağlayıp tek pas fragment shader ile drawable'a çizer.
///
/// AVSampleBufferDisplayLayer alternatifi: doğrudan CAMetalLayer ile çalışmak
/// ProMotion variable refresh sync, daha düşük latency (1 frame buffer azaltma),
/// HDR pipeline için tam kontrol sağlar. Aspect mode shader uniform'u ile uygulanır.
public final class MetalVideoView: MTKView {

    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var textureCache: CVMetalTextureCache!

    private let pendingLock = NSLock()
    private var pendingPixelBuffer: CVPixelBuffer?

    /// AVLayerVideoGravity karşılığı: resizeAspect (fit), resizeAspectFill (fill), resize (stretch).
    public var videoGravity: AVLayerVideoGravity = .resizeAspect {
        didSet {
            // Yeni gravity uygulansın diye bir kare daha çizdir.
            requestDraw()
        }
    }

    public init() {
        // macOS 14+ desteklenen tüm Mac'lerde Metal mevcut; bu nil yalnızca eski/test VM'lerde olur.
        guard let device = MTLCreateSystemDefaultDevice() else {
            Log.error("MetalVideoView", "MTLCreateSystemDefaultDevice nil — Metal yok, video render edilemez")
            fatalError("Metal cihazı bulunamadı: bu Mac/VM video oynatamaz")
        }
        super.init(frame: .zero, device: device)
        commonInit()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        guard let device = MTLCreateSystemDefaultDevice() else {
            Log.error("MetalVideoView", "MTLCreateSystemDefaultDevice nil (coder path)")
            fatalError("Metal cihazı bulunamadı: bu Mac/VM video oynatamaz")
        }
        self.device = device
        commonInit()
    }

    private func commonInit() {
        guard let device else { return }

        commandQueue = device.makeCommandQueue()
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = false
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        layer?.backgroundColor = NSColor.black.cgColor
        // Manuel draw mode: enqueuePixelBuffer her yeni karede draw() çağırır.
        // Bu sayede mpv'nin frame timing'i korunur; MTKView'ın kendi 60Hz CADisplayLink'i
        // gereksiz yere render yapmaz.
        isPaused = true
        enableSetNeedsDisplay = false
        // Drawable count düşük tutulursa latency az olur.
        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.maximumDrawableCount = 2
            metalLayer.framebufferOnly = false
            metalLayer.presentsWithTransaction = false
        }

        // Texture cache: CVPixelBuffer → MTLTexture sıfır-kopya köprü.
        var cache: CVMetalTextureCache?
        let result = CVMetalTextureCacheCreate(
            kCFAllocatorDefault, nil, device, nil, &cache
        )
        if result != kCVReturnSuccess || cache == nil {
            Log.error("MetalVideoView", "CVMetalTextureCacheCreate başarısız (\(result))")
        }
        self.textureCache = cache

        // Pipeline: default.metallib (xcodebuild Shaders.metal'i derler).
        do {
            let library = try device.makeDefaultLibrary(bundle: .main)
            let vert = library.makeFunction(name: "vertexMain")
            let frag = library.makeFunction(name: "fragmentMain")
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vert
            desc.fragmentFunction = frag
            desc.colorAttachments[0].pixelFormat = colorPixelFormat
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            Log.error("MetalVideoView", "pipeline state oluşturulamadı: \(error.localizedDescription)")
        }
    }

    /// mpv callback'i her thread'den çağırabilir; pixel buffer'ı atomik sakla,
    /// main thread'de draw tetikle.
    public func enqueuePixelBuffer(_ pixelBuffer: CVPixelBuffer, flipVerticalForOpenGL: Bool) {
        // OpenGL FBO çıkışı zaten doğru yönlü; flip=false bekleniyor.
        guard !flipVerticalForOpenGL else { return }
        pendingLock.lock()
        pendingPixelBuffer = pixelBuffer
        pendingLock.unlock()
        requestDraw()
    }

    public func flush() {
        pendingLock.lock()
        pendingPixelBuffer = nil
        pendingLock.unlock()
    }

    private func requestDraw() {
        if Thread.isMainThread {
            self.draw()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.draw()
            }
        }
    }

    /// MTKView varsayılan draw() override — currentDrawable / currentRenderPassDescriptor
    /// burada hazır. Her enqueuePixelBuffer sonrası çağrılır.
    override public func draw(_ rect: NSRect) {
        renderFrame()
    }

    private func renderFrame() {
        guard let pipelineState,
              let textureCache,
              let drawable = currentDrawable,
              let descriptor = currentRenderPassDescriptor else { return }

        pendingLock.lock()
        let pb = pendingPixelBuffer
        pendingLock.unlock()
        guard let pb else { return }

        let width = CVPixelBufferGetWidth(pb)
        let height = CVPixelBufferGetHeight(pb)
        guard width > 0, height > 0 else { return }

        var cvTextureOut: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pb,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTextureOut
        )
        guard status == kCVReturnSuccess,
              let cvTexture = cvTextureOut,
              let texture = CVMetalTextureGetTexture(cvTexture) else {
            Log.error("MetalVideoView", "CVMetalTextureCacheCreateTextureFromImage başarısız \(status)")
            return
        }

        // Aspect-preserving uniformlar
        let drawableSize = drawable.layer.drawableSize
        guard drawableSize.width > 0, drawableSize.height > 0 else { return }
        let uniforms = computeUniforms(
            textureWidth: CGFloat(width),
            textureHeight: CGFloat(height),
            viewWidth: drawableSize.width,
            viewHeight: drawableSize.height,
            gravity: videoGravity
        )

        guard let cmdBuf = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        encoder.setRenderPipelineState(pipelineState)
        var u = uniforms
        encoder.setVertexBytes(&u, length: MemoryLayout<VideoUniforms>.size, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    // MARK: - Aspect

    private struct VideoUniforms {
        var scale: SIMD2<Float>
        var texOffset: SIMD2<Float>
        var texScale: SIMD2<Float>
    }

    private func computeUniforms(
        textureWidth tw: CGFloat,
        textureHeight th: CGFloat,
        viewWidth vw: CGFloat,
        viewHeight vh: CGFloat,
        gravity: AVLayerVideoGravity
    ) -> VideoUniforms {
        let texAR = tw / th
        let viewAR = vw / vh
        var quadScale = SIMD2<Float>(1, 1)
        var texOffset = SIMD2<Float>(0, 0)
        var texScale  = SIMD2<Float>(1, 1)

        switch gravity {
        case .resizeAspect:
            // Fit: quad'i view'a göre küçült, texture full sample.
            if texAR > viewAR {
                quadScale = SIMD2<Float>(1, Float(viewAR / texAR))
            } else {
                quadScale = SIMD2<Float>(Float(texAR / viewAR), 1)
            }
        case .resizeAspectFill:
            // Fill: quad full, texture crop.
            if texAR > viewAR {
                // Texture daha geniş: dikeyi tam, yatayı crop.
                let s = Float(viewAR / texAR)
                texScale = SIMD2<Float>(s, 1)
                texOffset = SIMD2<Float>((1 - s) * 0.5, 0)
            } else {
                let s = Float(texAR / viewAR)
                texScale = SIMD2<Float>(1, s)
                texOffset = SIMD2<Float>(0, (1 - s) * 0.5)
            }
        default:
            // Stretch: quad full, texture full (varsayılan).
            break
        }

        return VideoUniforms(scale: quadScale, texOffset: texOffset, texScale: texScale)
    }
}
