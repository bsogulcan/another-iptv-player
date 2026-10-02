import Foundation

/// Downloads an EPG (XMLTV) guide to a temp file, handling conditional GET, size
/// guards, and transparent gzip. Returns a plain-XML file URL the caller must
/// delete when done.
nonisolated struct EPGDownloader {
    let urlSession: URLSession

    init(urlSession: URLSession = PanelURLSession.shared) {
        self.urlSession = urlSession
    }

    enum GuideDownload {
        case notModified
        /// Plain-XML file on disk plus refreshed conditional-GET validators.
        case file(URL, etag: String?, lastModified: String?)
    }

    /// - Parameters:
    ///   - etag/lastModified: prior validators for `If-None-Match`/`If-Modified-Since`.
    ///   - username/password: for credential redaction in thrown errors only.
    ///
    /// `@concurrent`: after the transfer this moves the file and may inflate a
    /// gzip body of up to `EPGConstants.maxInflatedBytes`, all synchronously. A
    /// plain nonisolated async function would do that on its caller's actor.
    @concurrent
    func downloadGuide(url: URL, etag: String?, lastModified: String?,
                       username: String? = nil, password: String? = nil) async throws -> GuideDownload {
        var request = URLRequest(url: url)
        // Force a network trip so a real 304 reaches us instead of URLCache
        // synthesizing a 200 from a cached body.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")

        let downloadedTemp: URL
        let response: URLResponse
        do {
            (downloadedTemp, response) = try await urlSession.download(for: request)
        } catch {
            throw EPGError.network(error)
        }

        // Move off the volatile download location immediately.
        let workURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("epg-\(UUID().uuidString).bin")
        try? FileManager.default.removeItem(at: workURL)
        do {
            try FileManager.default.moveItem(at: downloadedTemp, to: workURL)
        } catch {
            try? FileManager.default.removeItem(at: downloadedTemp)
            throw EPGError.network(error)
        }

        func cleanup() { try? FileManager.default.removeItem(at: workURL) }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 304 { cleanup(); return .notModified }
            guard (200...299).contains(http.statusCode) else {
                cleanup()
                throw EPGError.server(http.statusCode)
            }
        }

        // Size guard against the actual bytes on disk.
        let size = ((try? FileManager.default.attributesOfItem(atPath: workURL.path))?[.size] as? Int64) ?? 0
        if size > EPGConstants.maxCompressedBytes {
            cleanup()
            throw EPGError.tooLarge
        }

        let newEtag = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag")
        let newLastModified = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Last-Modified")

        // Sniff gzip magic (static `.gz` served as application/gzip is not
        // auto-inflated by URLSession).
        let head = try? readFirstBytes(workURL, count: 2)
        if let head, head.count == 2, head[head.startIndex] == 0x1f, head[head.startIndex + 1] == 0x8b {
            let xmlURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("epg-\(UUID().uuidString).xml")
            do {
                try GzipDecompressor.inflateFile(source: workURL, destination: xmlURL)
            } catch {
                cleanup(); try? FileManager.default.removeItem(at: xmlURL)
                throw error
            }
            cleanup()
            return .file(xmlURL, etag: newEtag, lastModified: newLastModified)
        }

        return .file(workURL, etag: newEtag, lastModified: newLastModified)
    }

    private func readFirstBytes(_ url: URL, count: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return (try handle.read(upToCount: count)) ?? Data()
    }
}
