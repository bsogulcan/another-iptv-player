import CloudKit
import Foundation

/// Alternate sync transport for users who don't want to run a self-hosted
/// server: stores the same generic sync items `SyncEngine` already builds
/// (`SyncWireItem` — kind/key/payload/updatedAt/deleted) as CKRecords in
/// this iCloud account's private database instead of pushing them over
/// HTTP. Mutually exclusive with the server backend — `SyncEngine.syncBackend`
/// picks exactly one active backend at a time.
///
/// Requires an "iCloud" capability with the CloudKit service enabled in
/// Xcode's Signing & Capabilities for this target, using container
/// identifier `Self.containerIdentifier` below. The SAME container
/// identifier must be selected on every platform target (iOS, macOS, tvOS)
/// for a user's devices to actually sync with each other — each platform's
/// *default* container otherwise differs per bundle ID and the three apps
/// would silently write to three separate, unrelated containers.
///
/// NOTE: the `CKFetchRecordZoneChangesOperation` block-based callback API
/// used in `pull(sinceToken:)` below is the one part of this file most
/// likely to need a small signature adjustment against the exact SDK
/// version you build with — this was written carefully but without a
/// compiler available to verify it (see the sync-server README's
/// "unverified by a compiler" note). Build this file first if something
/// doesn't compile.
final class CloudKitSyncTransport {
    static let containerIdentifier = "iCloud.dev.another-iptv-player.sync"
    private static let zoneName = "SyncZone"
    private static let recordType = "SyncItem"
    private static let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)

    private let container: CKContainer
    private let database: CKDatabase
    private var zoneReady = false

    init() {
        container = CKContainer(identifier: Self.containerIdentifier)
        database = container.privateCloudDatabase
    }

    func accountStatus() async -> CKAccountStatus {
        (try? await container.accountStatus()) ?? .couldNotDetermine
    }

    private func ensureZone() async throws {
        guard !zoneReady else { return }
        do {
            _ = try await database.save(CKRecordZone(zoneID: Self.zoneID))
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Zone already exists from a previous run — still usable.
        }
        zoneReady = true
    }

    private static func recordID(kind: String, key: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(kind)|\(key)", zoneID: zoneID)
    }

    private static func apply(_ item: SyncWireItem, to record: CKRecord) {
        record["kind"] = item.kind as CKRecordValue
        record["itemKey"] = item.key as CKRecordValue
        let payloadData = (try? JSONEncoder().encode(item.payload)) ?? Data("{}".utf8)
        record["payload"] = (String(data: payloadData, encoding: .utf8) ?? "{}") as CKRecordValue
        record["updatedAt"] = item.updatedAt as CKRecordValue
        record["deleted"] = (item.deleted ? Int64(1) : Int64(0)) as CKRecordValue
    }

    private static func copyFields(from source: CKRecord, onto destination: CKRecord) {
        destination["kind"] = source["kind"]
        destination["itemKey"] = source["itemKey"]
        destination["payload"] = source["payload"]
        destination["updatedAt"] = source["updatedAt"]
        destination["deleted"] = source["deleted"]
    }

    private static func pullItem(from record: CKRecord) -> SyncWireItem? {
        guard let kind = record["kind"] as? String,
              let key = record["itemKey"] as? String,
              let payloadString = record["payload"] as? String,
              let updatedAt = record["updatedAt"] as? Int64 else {
            return nil
        }
        let deletedRaw = record["deleted"] as? Int64 ?? 0
        let payload = (try? JSONDecoder().decode(SyncPayload.self, from: Data(payloadString.utf8))) ?? .empty
        return SyncWireItem(kind: kind, key: key, payload: payload, updatedAt: updatedAt, deleted: deletedRaw != 0)
    }

    /// Upserts each item as a CKRecord. On a write conflict (another device
    /// already pushed a newer version of the same item since our last
    /// pull), the newer `updatedAt` wins — same last-write-wins policy as
    /// the self-hosted server, just resolved client-side via CloudKit's
    /// optimistic concurrency error instead of a database transaction.
    func push(items: [SyncWireItem]) async throws {
        guard !items.isEmpty else { return }
        try await ensureZone()

        var recordsToSave: [CKRecord] = []
        recordsToSave.reserveCapacity(items.count)
        for item in items {
            let record = CKRecord(recordType: Self.recordType, recordID: Self.recordID(kind: item.kind, key: item.key))
            Self.apply(item, to: record)
            recordsToSave.append(record)
        }

        let result = try await database.modifyRecords(
            saving: recordsToSave,
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: false
        )

        var retries: [CKRecord] = []
        for (recordID, saveResult) in result.saveResults {
            guard case .failure(let error) = saveResult,
                  let ckError = error as? CKError,
                  ckError.code == .serverRecordChanged,
                  let serverRecord = ckError.serverRecord,
                  let ourRecord = recordsToSave.first(where: { $0.recordID == recordID }) else {
                continue
            }
            let ourUpdatedAt = ourRecord["updatedAt"] as? Int64 ?? 0
            let serverUpdatedAt = serverRecord["updatedAt"] as? Int64 ?? 0
            guard ourUpdatedAt >= serverUpdatedAt else { continue } // server's write is newer — it wins
            Self.copyFields(from: ourRecord, onto: serverRecord)
            retries.append(serverRecord)
        }

        if !retries.isEmpty {
            _ = try? await database.modifyRecords(saving: retries, deleting: [], savePolicy: .changedKeys, atomically: false)
        }
    }

    struct PullResult {
        var items: [SyncWireItem]
        var changeTokenData: Data?
        var hasMore: Bool
    }

    /// Delta-fetches everything changed in our zone since `tokenData`
    /// (`nil` fetches everything, for a first sync or after `resetCursor()`).
    func pull(sinceToken tokenData: Data?) async throws -> PullResult {
        try await ensureZone()
        let token: CKServerChangeToken? = tokenData.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            config.previousServerChangeToken = token
            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [Self.zoneID],
                configurationsByRecordZoneID: [Self.zoneID: config]
            )
            operation.fetchAllChanges = false

            var collected: [SyncWireItem] = []
            var newToken: CKServerChangeToken?
            var moreComing = false
            var failure: Error?

            operation.recordWasChangedBlock = { _, result in
                if case .success(let record) = result, let item = Self.pullItem(from: record) {
                    collected.append(item)
                }
            }
            operation.recordZoneFetchResultBlock = { _, result in
                switch result {
                case .success(let success):
                    newToken = success.serverChangeToken
                    moreComing = success.moreComing
                case .failure(let error):
                    failure = error
                }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                if case .failure(let error) = result {
                    continuation.resume(throwing: failure ?? error)
                    return
                }
                if let failure {
                    continuation.resume(throwing: failure)
                    return
                }
                let encodedToken = newToken.flatMap {
                    try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
                }
                continuation.resume(returning: PullResult(items: collected, changeTokenData: encodedToken, hasMore: moreComing))
            }
            database.add(operation)
        }
    }
}

enum SyncCloudError: LocalizedError {
    case accountUnavailable(CKAccountStatus)

    var errorDescription: String? {
        switch self {
        case .accountUnavailable(let status):
            switch status {
            case .noAccount: return L("sync.error.icloud_no_account")
            case .restricted: return L("sync.error.icloud_restricted")
            default: return L("sync.error.icloud_unavailable")
            }
        }
    }
}
