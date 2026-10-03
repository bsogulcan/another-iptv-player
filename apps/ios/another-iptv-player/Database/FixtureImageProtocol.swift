import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Only installed for explicitly launched rich/large UI fixtures. Uses the real
/// URLSession/Nuke decoding path, without an external image server. Responses are
/// synchronous on the loading thread; there is no simulated network latency.
nonisolated final class FixtureImageProtocol: URLProtocol {
    static let host = "browse-fixture.invalid"
    private static let renderSlots = DispatchSemaphore(value: 4)
    private let lock = NSRecursiveLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == host
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.renderSlots.wait()
        defer { Self.renderSlots.signal() }
        guard let url = request.url else { return }
        let components = url.pathComponents
        let width = min(1280, max(32, Int(components.dropLast().last ?? "") ?? 400))
        let height = min(1280, max(32, Int(components.last ?? "") ?? 600))
        let data = Self.artwork(seed: url.path, width: width, height: height)
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return }
        guard let data else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotDecodeContentData))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "image/jpeg", "Content-Length": "\(data.count)"] )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        guard !stopped else { return }
        client?.urlProtocol(self, didLoad: data)
        guard !stopped else { return }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    /// Repeatable textured gradients exercise JPEG decode rather than a tiny flat
    /// swatch. This synthetic texture is not a claim about real CDN latency/cost.
    static func artwork(seed: String, width: Int, height: Int) -> Data? {
        var state = seed.utf8.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                state = state &* 6364136223846793005 &+ 1
                let noise = Int((state >> 32) & 31)
                let index = (y * width + x) * 4
                pixels[index] = UInt8(min(255, 25 + x * 150 / width + noise))
                pixels[index + 1] = UInt8(min(255, 30 + y * 130 / height + noise))
                pixels[index + 2] = UInt8(min(255, 70 + (x + y) * 100 / (width + height) + noise))
            }
        }
        return pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
                  let image = context.makeImage() else { return nil }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return output as Data
        }
    }
}
