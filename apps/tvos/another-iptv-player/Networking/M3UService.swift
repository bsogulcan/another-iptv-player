import Foundation

enum M3UServiceError: LocalizedError {
    case invalidURL(String)
    case networkError(Error)
    case serverError(Int)
    case fileReadError(Error)
    case encodingUnsupported

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return L("net.error.invalid_url", url)
        case .networkError(let err): return L("net.error.network", err.localizedDescription)
        case .serverError(let code): return L("net.error.server", code)
        case .fileReadError(let err): return L("net.error.file_read", err.localizedDescription)
        case .encodingUnsupported: return L("net.error.encoding_unsupported")
        }
    }
}

/// M3U/M3U8 içeriğini uzak URL'den indirmek veya yerel dosyadan okumak.
struct M3UService {
    let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func fetchRemote(urlString: String) async throws -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw M3UServiceError.invalidURL(urlString)
        }

        do {
            let (data, response) = try await urlSession.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw M3UServiceError.serverError(http.statusCode)
            }
            return try decode(data: data)
        } catch let e as M3UServiceError {
            throw e
        } catch {
            throw M3UServiceError.networkError(error)
        }
    }

    func readLocal(url: URL) throws -> String {
        // Security-scoped resource (fileImporter URL'leri için şart).
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            return try decode(data: data)
        } catch let e as M3UServiceError {
            throw e
        } catch {
            throw M3UServiceError.fileReadError(error)
        }
    }

    // MARK: - Decoding

    private func decode(data: Data) throws -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        if let s = String(data: data, encoding: .utf16) { return s }
        throw M3UServiceError.encodingUnsupported
    }
}
