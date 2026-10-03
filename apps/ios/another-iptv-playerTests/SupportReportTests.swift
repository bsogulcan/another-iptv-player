import Foundation
import Testing
@testable import another_iptv_player

struct SupportReportTests {
    @Test func exportRemovesURLsAndStructuredCredentials() {
        let output = SupportReport.sanitized("""
        Failed https://private.example/movie/alice/secret/12.ts?token=abc
        {"username": "alice", "password": "secret", "access_token": "abc"}
        Authorization: Bearer xyz
        Authorization: Basic c2VjcmV0
        cookie=session123 token=def
        decoder failed: 42
        """)
        for secret in ["private.example", "alice", "secret", "abc", "xyz", "c2VjcmV0", "session123", "def"] {
            #expect(!output.contains(secret))
        }
        #expect(output.contains("decoder failed: 42"))
    }

    @Test func attachmentIsOnlyIncludedWhenRequested() {
        let report = SupportReport(subject: "Contact", body: "Hello", diagnostics: nil)
        #expect(report.attachment == nil)
        #expect(report.shareText.contains(SupportReport.recipient))
        let issue = SupportReport(subject: "Issue", body: "Hello", diagnostics: "safe log")
        #expect(issue.attachment == Data("safe log".utf8))
    }

    @Test func previousAirPlaySessionIsDatedAndSeparate() {
        let output = SupportReport.diagnosticsText(current: ["current"], savedAirPlay: ["previous"], savedAt: Date(timeIntervalSince1970: 0))
        #expect(output.contains("1970-01-01T00:00:00Z"))
        #expect(output.contains("current"))
        #expect(output.contains("previous"))
        #expect(!SupportReport.diagnosticsText(current: [], savedAirPlay: [], savedAt: nil).contains("AirPlay"))
    }
}
