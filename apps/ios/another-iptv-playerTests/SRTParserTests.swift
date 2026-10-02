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

    @Test
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

    // MARK: - Markup

    @Test
    func stripsDisplayMarkupFromCueText() throws {
        let srt = #"""
        1
        00:00:01,000 --> 00:00:04,000
        <i>Italic</i> and <B>bold</B>
        <font color="#ffff00">Coloured</font> {\an8}top {i}old style{/i}

        """#
        let entries = SRTParser().parse(content: srt)
        try #require(entries.count == 1)
        #expect(entries[0].text == "Italic and bold\nColoured top old style")
    }

    /// A tag on a line of its own must not leave an empty row in the cue.
    @Test
    func dropsLinesThatWereOnlyMarkup() throws {
        let srt = #"""
        1
        00:00:01,000 --> 00:00:04,000
        <i>
        Hello
        </i>
        {\an8}

        """#
        let entries = SRTParser().parse(content: srt)
        try #require(entries.count == 1)
        #expect(entries[0].text == "Hello")
    }

    /// Only known tags are markup; dialogue that happens to use brackets stays.
    @Test
    func keepsBracketsThatAreNotMarkup() {
        let line = "a < b, <because> and <br> {laughs}"
        #expect(SRTParser.strippingMarkupTags(line) == line)
        #expect(SRTParser.strippingOverrideBlocks(line) == line)
    }

    @Test
    func stripsWebVTTTags() {
        let line = "<v Roger>Hi <c.yellow.bg_blue>there</c> <00:00:01.500>now</v>"
        #expect(SRTParser.strippingMarkupTags(line) == "Hi there now")
    }

    @Test
    func stripsOverrideBlocks() {
        #expect(SRTParser.strippingOverrideBlocks(#"{\an8}Top {\i1}italic{\i0} {\pos(10,20)}here"#) == "Top italic here")
    }

    /// On a whole file a tag-only line is removed with its line break: a blank line in
    /// its place would end the cue before its text.
    @Test
    func removesTagOnlyLinesFromWholeFile() {
        let file = "1\n00:00:01,000 --> 00:00:02,000\n<i>\nHello\n</i>\n\n2\n00:00:03,000 --> 00:00:04,000\n<b>Bye</b>\n"
        let expected = "1\n00:00:01,000 --> 00:00:02,000\nHello\n\n2\n00:00:03,000 --> 00:00:04,000\nBye\n"
        #expect(SRTParser.strippingMarkupTags(file) == expected)
    }
}
