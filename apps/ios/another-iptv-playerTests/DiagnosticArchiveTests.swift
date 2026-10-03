import Foundation
import Testing
@testable import another_iptv_player

struct DiagnosticArchiveTests {
    @Test func survivesRecreationAndMasksBeforeWriting() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = DiagnosticArchive(directory: directory)
        archive.append("Playback started password=secret https://private.example/movie/user/pass/1")
        let text = archive.snapshot()
        #expect(text.contains("Playback started"))
        #expect(!text.contains("secret"))
        #expect(!text.contains("private.example"))
        #expect(DiagnosticArchive(directory: directory).snapshot() == text)
    }

    @Test func rotationBoundsDiskUsageAndKeepsNewest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = DiagnosticArchive(directory: directory, fileLimit: 1024, fileCount: 2)
        for index in 0..<20 { archive.append("event-\(index) " + String(repeating: "x", count: 350)) }
        let text = archive.snapshot()
        #expect(text.contains("event-19"))
        #expect(!text.contains("event-0 "))
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        #expect(files.count <= 2)
        for file in files { #expect(try Data(contentsOf: file).count <= 1024) }
    }

    @Test func expiredRecordsAreRemovedOnRead() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = DiagnosticArchive(directory: directory, lifetime: 60)
        archive.append("old")
        _ = archive.snapshot()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for file in files { try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -120)], ofItemAtPath: file.path) }
        #expect(archive.snapshot().isEmpty)
    }

    @Test func rawJSONRetainsDecoderRelevantTypesWithoutSecrets() throws {
        let data = Data(#"{"rating":null,"episode_num":"bad","duration":42,"password":"s\"ecret","nested":{"access_token":"xyz","url":"https:\/\/host\/user\/password"},"episodes":[1,2]}"#.utf8)
        let text = APIDiagnostics.body(data)
        let object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(object["rating"] is NSNull)
        #expect(object["episode_num"] as? String == "bad")
        #expect(object["duration"] as? Int == 42)
        #expect(!text.contains("ecret"))
        #expect(!text.contains("xyz"))
        #expect(!text.contains("host"))
    }

    @Test func malformedAndOversizedResponsesAreBoundedAndMasked() {
        let raw = "{\"password\":\"unfinished-secret " + String(repeating: "x", count: 100_000)
        let text = APIDiagnostics.body(Data(raw.utf8))
        #expect(!text.contains("unfinished-secret"))
        #expect(text.contains("truncated"))
        #expect(text.utf8.count < APIDiagnostics.bodyLimit + 100)
    }

    @Test func skippedItemsRetainDecodeFailure() throws {
        struct Item: Decodable { let id: Int }
        let items = try JSONDecoder().decode([FailableDecodable<Item>].self, from: Data(#"[{"id":1},{"id":"bad"}]"#.utf8))
        #expect(items[0].base?.id == 1)
        #expect(items[1].base == nil)
        #expect(items[1].failure?.contains("id") == true)
    }
    @Test func knownCredentialsDoNotAlterJSONKeysOrNumbers() throws {
        let data = Data(#"{"password":"pass","username":"user","episode":123,"title":"example","unexpected":"pass"}"#.utf8)
        let text = APIDiagnostics.body(data, secrets: ["pass", "user", "123"])
        let object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(object["password"] as? String == "<redacted>")
        #expect(object["username"] as? String == "<redacted>")
        #expect(object["episode"] as? Int == 123)
        #expect(object["unexpected"] as? String == "<credential>")
    }

    @Test func exportKeepsNewestArchivedRecordsAfterLargeBody() {
        let archive = String(repeating: "x", count: 210_000) + "\nLatest player failure"
        let text = SupportReport.diagnosticsText(current: [], savedAirPlay: [], savedAt: nil, archive: archive)
        #expect(text.contains("Latest player failure"))
    }

    @MainActor @Test func successfulDetailResponseReachesSupportArchive() async throws {
        let host = "diagnostics-\(UUID().uuidString.lowercased()).invalid"
        let marker = "Film-\(UUID().uuidString)"
        let secret = "secret-\(UUID().uuidString)"
        let body = "{\"info\":{\"name\":\"\(marker)\",\"password\":\"\(secret)\"},\"movie_data\":{\"stream_id\":7}}"
        XtreamStubURLProtocol.setAnswer(.init(status: 200, body: Data(body.utf8)), forHost: host)
        defer { XtreamStubURLProtocol.setAnswer(nil, forHost: host) }
        let playlist = Playlist(name: "Test", serverURL: "https://\(host)", username: "test-account", password: secret)
        let client = XtreamAPIClient(playlist: playlist, urlSession: XtreamStubURLProtocol.makeSession())
        let result = try await client.getVODInfo(vodId: 7)
        #expect(result.info?.name == marker)
        let text = await Task.detached { DiagnosticArchive.shared.snapshot() }.value
        #expect(text.contains(marker))
        #expect(text.contains("[APIResponse] get_vod_info"))
        #expect(!text.contains(secret))
    }

    @Test func batchesWritesAndReusesHandleWithoutLosingLines() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = DiagnosticArchive(directory: directory, flushInterval: 60)
        for index in 0..<100 { archive.append("batch-event-\(index)\n") }
        let text = archive.snapshot()
        for index in 0..<100 { #expect(text.contains("batch-event-\(index)\n")) }
        #expect(archive.ioCounts().writes == 1)
        archive.append("next batch")
        archive.flush()
        #expect(archive.ioCounts().writes == 2)
        #expect(archive.ioCounts().opens == 1)
    }

    @Test func queueDoesNotBlockProducerAndBoundsPendingWork() {
        let worker = DiagnosticWorkQueue(label: "test.blocked-diagnostics", countLimit: 3, byteLimit: 10)
        let gate = DispatchSemaphore(value: 0)
        worker.queue.async { gate.wait() }
        defer { gate.signal() }
        #expect(worker.submit(bytes: 4) {})
        #expect(worker.submit(bytes: 4) {})
        #expect(!worker.submit(bytes: 4) {})
        #expect(worker.submit(bytes: 1) {})
        #expect(!worker.submit(bytes: 0) {})
        #expect(worker.skippedCount == 2)
    }

    @Test func oversizedJobIsRejectedWithoutRunning() {
        let worker = DiagnosticWorkQueue(label: "test.oversized-diagnostics", byteLimit: 10)
        #expect(!worker.submit(bytes: 11) { Issue.record("Oversized work ran") })
        worker.flush()
        #expect(worker.skippedCount == 1)
    }

    @Test func timerFlushesWithoutOpeningAReport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = DiagnosticArchive(directory: directory, flushInterval: 0.01)
        archive.append("background write password=hidden")
        for _ in 0..<100 {
            if archive.ioCounts().writes > 0 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(archive.ioCounts().writes == 1)
        let text = try String(contentsOf: directory.appendingPathComponent("events-0.log"), encoding: .utf8)
        #expect(text.contains("background write"))
        #expect(!text.contains("hidden"))
    }

}
