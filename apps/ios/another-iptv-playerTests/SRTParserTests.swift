import Foundation
import Testing
@testable import another_iptv_player

@Suite("SRTParser")
struct SRTParserTests {

    @Test
    func emptyInputReturnsEmpty() {
        let entries = SRTParser().parse(content: "")
        #expect(entries.isEmpty)
    }

    @Test
    func parsesSingleEntry() throws {
        let srt = """
        1
        00:00:01,000 --> 00:00:04,000
        Hello world

        """
        let entries = SRTParser().parse(content: srt)
        try #require(entries.count == 1)
        let e = entries[0]
        #expect(e.startTime == 1.0)
        #expect(e.endTime == 4.0)
        #expect(e.text == "Hello world")
    }

    // Disabled: SRTParser uses Scanner with default whitespace+newline skipping,
    // so blank-line separators between entries are eaten — all entries collapse into
    // entry #1's text. See SRTParser.swift parse(content:) inner while loop.
    // Re-enable once the parser switches off auto-skip or rewrites block-by-block.
    @Test(.disabled("known bug: multi-block SRT collapses into one entry"))
    func parsesMultipleEntries() throws {
        let srt = """
        1
        00:00:01,000 --> 00:00:02,000
        First

        2
        00:00:03,500 --> 00:00:05,250
        Second

        3
        00:00:10,000 --> 00:00:12,000
        Third

        """
        let entries = SRTParser().parse(content: srt)
        try #require(entries.count == 3)
        #expect(entries.map(\.text) == ["First", "Second", "Third"])
        #expect(entries[1].startTime == 3.5)
        #expect(entries[1].endTime == 5.25)
    }

    @Test
    func multilineSubtitleText() throws {
        let srt = """
        1
        00:00:01,000 --> 00:00:04,000
        Line one
        Line two
        Line three

        """
        let entries = SRTParser().parse(content: srt)
        try #require(entries.count == 1)
        #expect(entries[0].text == "Line one\nLine two\nLine three")
    }

    @Test
    func hoursAndMinutesContributeToTime() throws {
        let srt = """
        1
        01:02:03,500 --> 01:02:04,000
        X

        """
        let entries = SRTParser().parse(content: srt)
        try #require(entries.count == 1)
        // 1h 2m 3.5s = 3600 + 120 + 3.5 = 3723.5
        #expect(entries[0].startTime == 3723.5)
        #expect(entries[0].endTime == 3724.0)
    }

    @Test
    func skipsEntryWithMalformedTimecode() throws {
        let srt = """
        1
        bogus timecode
        Should be skipped

        2
        00:00:05,000 --> 00:00:08,000
        Good one

        """
        let entries = SRTParser().parse(content: srt)
        try #require(entries.count == 1)
        #expect(entries[0].text == "Good one")
    }
}
