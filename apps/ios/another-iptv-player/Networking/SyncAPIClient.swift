import Foundation

/// Wire types for the self-hosted sync-server API (see
/// `services/sync-server/README.md` in the repo root for the full
/// contract). `SyncPayload` is a superset of every kind's payload shape;
/// unused fields simply stay nil and are omitted by `JSONEncoder` (an
/// all-nil `SyncPayload` encodes to `{}`), so one Codable type covers
/// `favorite`, `progress`, and `hidden_category` without a hand-rolled
/// dynamic-JSON type.
struct SyncPayload: Codable, Equatable {
    var positionSeconds: Double?
    var durationSeconds: Double?
    var title: String?
    var secondaryTitle: String?
    var imageURL: String?
    var containerExtension: String?
    /// Always a string on the wire so it round-trips losslessly across
    /// platforms whose native id type for it differs (Android's is a
    /// string; this app's `DBWatchHistory.seriesId` already is too).
    var seriesId: String?

    static let empty = SyncPayload()
}

struct SyncWireItem: Codable {
    var kind: String
    var key: String
    var payload: SyncPayload
    var updatedAt: Int64
    var deleted: Bool
}

struct SyncPushResultItem: Decodable {
    var kind: String
    var key: String
    var status: String
}

struct SyncPullResult {
    var items: [SyncWireItem]
    var cursor: Int64
    var hasMore: Bool
}

private struct SyncPushRequestBody: Encodable { var items: [SyncWireItem] }
private struct SyncPushResponseBody: Decodable { var results: [SyncPushResultItem] }
private struct SyncPullResponseBody: Decodable { var items: [SyncWireItem]; var cursor: Int64; var hasMore: Bool }
private struct SyncRegisterRequestBody: Encodable { var username: String; var password: String }
private struct SyncTokenRequestBody: Encodable { var username: String; var password: String; var deviceName: String }
private struct SyncErrorBody: Decodable { var error: String? }

struct SyncTokenResponse: Decodable {
    var token: String
    var deviceId: Int64
    var deviceName: String
}

struct SyncDeviceInfo: Decodable, Identifiable {
    var id: Int64
    var deviceName: String
    var createdAt: Int64
    var lastSeenAt: Int64
    var revoked: Bool
    var current: Bool
}

private struct SyncDevicesResponseBody: Decodable { var devices: [SyncDeviceInfo] }

enum SyncAPIError: LocalizedError {
    case invalidURL
    case network(Error)
    case server(status: Int, message: String?)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return L("sync.error.invalid_url")
        case .network(let error): return L("net.error.network", error.localizedDescription)
        case .server(let status, let message): return message ?? L("sync.error.server_status", status)
        case .decoding(let error): return L("misc.xtream.decode_error", error.localizedDescription)
        }
    }
}

/// Talks to a self-hosted sync-server instance (see `services/sync-server`).
/// Swift counterpart of the Tizen client's `sync/api.ts`.
final class SyncAPIClient {
    private let session: URLSession

    init(session: URLSession = PanelURLSession.shared) {
        self.session = session
    }

    private func normalize(_ serverURL: String) -> String {
        var base = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.lowercased().hasPrefix("http://") && !base.lowercased().hasPrefix("https://") {
            base = "http://\(base)"
        }
        if base.hasSuffix("/") { base.removeLast() }
        return base
    }

    private func request(
        path: String,
        method: String,
        serverURL: String,
        jsonBody: Data? = nil,
        token: String? = nil
    ) async throws -> Data {
        guard let url = URL(string: normalize(serverURL) + path) else {
            throw SyncAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let jsonBody {
            req.httpBody = jsonBody
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw SyncAPIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SyncAPIError.network(URLError(.badServerResponse))
        }
        guard (200...299).contains(http.statusCode) else {
            var message: String?
            if let decoded = try? JSONDecoder().decode(SyncErrorBody.self, from: data) {
                message = decoded.error
            }
            throw SyncAPIError.server(status: http.statusCode, message: message)
        }
        return data
    }

    func register(serverURL: String, username: String, password: String) async throws {
        let body = try JSONEncoder().encode(SyncRegisterRequestBody(username: username, password: password))
        _ = try await request(path: "/api/auth/register", method: "POST", serverURL: serverURL, jsonBody: body)
    }

    func requestDeviceToken(
        serverURL: String,
        username: String,
        password: String,
        deviceName: String
    ) async throws -> SyncTokenResponse {
        let body = try JSONEncoder().encode(
            SyncTokenRequestBody(username: username, password: password, deviceName: deviceName)
        )
        let data = try await request(path: "/api/auth/token", method: "POST", serverURL: serverURL, jsonBody: body)
        do {
            return try JSONDecoder().decode(SyncTokenResponse.self, from: data)
        } catch {
            throw SyncAPIError.decoding(error)
        }
    }

    func listDevices(serverURL: String, token: String) async throws -> [SyncDeviceInfo] {
        let data = try await request(path: "/api/auth/devices", method: "GET", serverURL: serverURL, token: token)
        do {
            return try JSONDecoder().decode(SyncDevicesResponseBody.self, from: data).devices
        } catch {
            throw SyncAPIError.decoding(error)
        }
    }

    func revokeDevice(serverURL: String, token: String, deviceId: Int64) async throws {
        _ = try await request(
            path: "/api/auth/devices/\(deviceId)",
            method: "DELETE",
            serverURL: serverURL,
            token: token
        )
    }

    func push(items: [SyncWireItem], serverURL: String, token: String) async throws -> [SyncPushResultItem] {
        let body = try JSONEncoder().encode(SyncPushRequestBody(items: items))
        let data = try await request(path: "/api/sync/push", method: "POST", serverURL: serverURL, jsonBody: body, token: token)
        do {
            return try JSONDecoder().decode(SyncPushResponseBody.self, from: data).results
        } catch {
            throw SyncAPIError.decoding(error)
        }
    }

    func pull(since: Int64, serverURL: String, token: String) async throws -> SyncPullResult {
        let data = try await request(
            path: "/api/sync/pull?since=\(since)&limit=1000",
            method: "GET",
            serverURL: serverURL,
            token: token
        )
        do {
            let decoded = try JSONDecoder().decode(SyncPullResponseBody.self, from: data)
            return SyncPullResult(items: decoded.items, cursor: decoded.cursor, hasMore: decoded.hasMore)
        } catch {
            throw SyncAPIError.decoding(error)
        }
    }
}
