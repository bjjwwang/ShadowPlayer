import Testing
#if SWIFT_PACKAGE
@testable import ShadowingCore
#else
@testable import ShadowingPlayer
#endif

final class SubtitleTests {
    @Test func testTimestampMillisecondsAndHours() {
        #expect(SubtitleParser.timestamp("00:00:01,200") == 1.2)
        #expect(SubtitleParser.timestamp(" 12:34:56,789 ") == 45_296.789)
        #expect(SubtitleParser.timestamp("100:00:00,001") == 360_000.001)
    }

    @Test func testMalformedTimestamps() {
        for text in ["00:60:00,000", "00:00:60,000", "-1:00:00,000", "00:00:00,12", "00:00:00.123", "1:00:00,000", "00:0:00,000", "aa:00:00,000", "999999999999999999999:00:00,000"] {
            #expect(SubtitleParser.timestamp(text) == nil)
        }
    }

    @Test func testUTF8BOMCRLFMultilineAndSorting() {
        let text = "\u{FEFF}2\r\n00:00:05,000 --> 00:00:09,100\r\nCafé — second\r\nAnother line\r\n \r\n1\r\n00:00:01,200 --> 00:00:04,800\r\nFirst\r\n"
        let result = SubtitleParser.parse(text)
        #expect(result.skippedEntries == 0)
        #expect(result.segments.map(\.text) == ["First", "Café — second\nAnother line"])
        #expect(result.segments[0].startTime == 1.2)
        #expect(result.segments[0].endTime == 4.8)
    }

    @Test func testMalformedEntriesSkippedWithoutDiscardingGoodEntries() {
        let text = """
        1
        bad --> 00:00:03,000
        Bad timestamp

        2
        00:00:04,000 --> 00:00:03,000
        Reversed

        3
        00:00:04,000 --> 00:00:04,000
        Empty interval

        4
        00:00:04,000 --> 00:00:05,000

        5
        00:00:05,000 --> 00:00:06,000
        Valid
        """
        let result = SubtitleParser.parse(text)
        #expect(result.skippedEntries == 4)
        #expect(result.segments.map(\.text) == ["Valid"])
    }

    @Test func testEmptyInput() {
        #expect(SubtitleParser.parse("\u{FEFF}\r\n \n").segments.isEmpty)
        #expect(SubtitleParser.parse("").skippedEntries == 0)
    }

    @Test func testMissingAndDuplicateIndicesHaveUniqueIDs() {
        let result = SubtitleParser.parse("00:00:00,000 --> 00:00:01,000\nNo index\n\n1\n00:00:01,000 --> 00:00:02,000\nOne\n\n1\n00:00:02,000 --> 00:00:03,000\nDuplicate")
        #expect(result.segments.count == 3)
        #expect(Set(result.segments.map(\.id)).count == 3)
    }

    private func segment(_ id: Int, _ start: Double, _ end: Double) -> SubtitleSegment {
        SubtitleSegment(id: id, startTime: start, endTime: end, text: "\(id)")
    }

    @Test func testHalfOpenBoundariesAdjacentEntriesAndGaps() {
        let timeline = SubtitleTimeline(segments: [segment(1, 1, 2), segment(2, 2, 3), segment(3, 4, 5)])
        #expect(timeline.activeID(at: 0.999, offset: 0) == nil)
        #expect(timeline.activeID(at: 1, offset: 0) == 1)
        #expect(timeline.activeID(at: 1.999, offset: 0) == 1)
        #expect(timeline.activeID(at: 2, offset: 0) == 2)
        #expect(timeline.activeID(at: 3, offset: 0) == nil)
        #expect(timeline.activeID(at: 3.999, offset: 0) == nil)
        #expect(timeline.activeID(at: 4, offset: 0) == 3)
        #expect(timeline.activeID(at: 5, offset: 0) == nil)
    }

    @Test func testBothOffsetDirectionsPreserveSourceTimestamps() {
        let timeline = SubtitleTimeline(segments: [segment(1, 2, 3)])
        #expect(timeline.activeID(at: 2.5, offset: 0.5) == 1)
        #expect(timeline.activeID(at: 2, offset: 0.5) == nil)
        #expect(timeline.activeID(at: 1.5, offset: -0.5) == 1)
        #expect(timeline.activeID(at: 2.5, offset: -0.5) == nil)
        #expect(timeline.segments[0].startTime == 2)
        #expect(timeline.segments[0].endTime == 3)
    }

    @Test func testOverlapsChooseLatestStartAndFallBackToEarlierLongEntry() {
        let timeline = SubtitleTimeline(segments: [segment(1, 1, 10), segment(2, 2, 3), segment(3, 2, 4), segment(4, 5, 6)])
        #expect(timeline.activeID(at: 2, offset: 0) == 3)
        #expect(timeline.activeID(at: 3.5, offset: 0) == 3)
        #expect(timeline.activeID(at: 4, offset: 0) == 1)
        #expect(timeline.activeID(at: 5, offset: 0) == 4)
        #expect(timeline.activeID(at: 6, offset: 0) == 1)
        #expect(timeline.activeID(at: 10, offset: 0) == nil)
    }

    @Test func testUnsortedAndLongTimelineLookup() {
        let entries = (0..<10_000).reversed().map { segment($0, Double($0) * 2, Double($0) * 2 + 1) }
        let timeline = SubtitleTimeline(segments: entries)
        #expect(timeline.activeID(at: 19_998.5, offset: 0) == 9_999)
        #expect(timeline.activeID(at: 19_999, offset: 0) == nil)
        #expect(timeline.activeID(at: 0, offset: 0) == 0)
    }

    @Test func testEmptyAndNonFiniteLookup() {
        #expect(SubtitleTimeline(segments: []).activeID(at: 0, offset: 0) == nil)
        let timeline = SubtitleTimeline(segments: [segment(1, 0, 10)])
        #expect(timeline.activeID(at: .nan, offset: 0) == nil)
        #expect(timeline.activeID(at: 1, offset: .infinity) == nil)
    }
}
