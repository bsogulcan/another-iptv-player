import Foundation
import Testing
@testable import another_iptv_player

struct DiagnosticPreviewTests {
    @Test func largeSingleLineIsBoundedAndAttachmentIsComplete() {
        let text = "START" + String(repeating: "x", count: 1_500_000) + "LATEST"
        let preview = DiagnosticPreview(text: text)
        #expect(preview.pages.count > 300)
        #expect(preview.pages.allSatisfy { $0.utf8.count <= DiagnosticPreview.pageByteLimit })
        #expect(preview.pages.joined() == text)
        #expect(preview.pages.last?.hasSuffix("LATEST") == true)
        let report = SupportReport(subject: "Issue", body: "", diagnostics: text)
        #expect(report.attachment == Data(text.utf8))
    }

    @Test func manyShortLinesAlsoHaveABoundedLayout() {
        let text = String(repeating: "event\n", count: 100_000)
        let preview = DiagnosticPreview(text: text)
        #expect(preview.pages.allSatisfy { $0.filter { $0 == "\n" }.count <= DiagnosticPreview.pageLineLimit })
        #expect(preview.pages.joined() == text)
    }

    @Test func unicodeAndEmptyReportsRemainReadable() {
        let text = String(repeating: "Türkçe 👩🏽‍💻 中文 العربية e\u{301}\n", count: 3000)
        let preview = DiagnosticPreview(text: text)
        #expect(preview.pages.joined() == text)
        #expect(preview.pages.allSatisfy { !$0.contains("\u{FFFD}") && $0.utf8.count <= DiagnosticPreview.pageByteLimit })
        #expect(DiagnosticPreview(text: "").pages == [""])
    }

    @Test func manySensitiveFieldsKeepTheirSurroundingUnicodeAndJSON() {
        let input = String(repeating: "{\"title\":\"中文👩🏽‍💻\",\"password\":\"secret\",\"token\":\"abc\"}\n", count: 20_000)
        let output = SupportReport.sanitized(input)
        let expected = String(repeating: "{\"title\":\"中文👩🏽‍💻\",\"password\":\"<redacted>\",\"token\":\"<redacted>\"}\n", count: 20_000)
        #expect(output == expected)
    }
}
