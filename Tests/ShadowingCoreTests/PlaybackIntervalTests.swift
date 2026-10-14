import Testing
#if SWIFT_PACKAGE
@testable import ShadowingCore
#else
@testable import ShadowingPlayer
#endif

final class PlaybackIntervalTests {
    private let segment = SubtitleSegment(id: 1, startTime: 1, endTime: 2, text: "Test")

    @Test func testPaddingAndOffset() throws {
        let bounds = try #require(PlaybackInterval.subtitle(segment, offset: 0.5, padding: 0.15, duration: 10))
        #expect(abs(bounds.start - 1.35) <= 0.000_001)
        #expect(abs(bounds.end - 2.65) <= 0.000_001)
        let earlier = try #require(PlaybackInterval.subtitle(segment, offset: -0.5, padding: 0, duration: 10))
        #expect(earlier.start == 0.5)
        #expect(earlier.end == 1.5)
    }

    @Test func testPaddingClampedToZeroThrough300Milliseconds() throws {
        let low = try #require(PlaybackInterval.subtitle(segment, offset: 0, padding: -1, duration: 10))
        let high = try #require(PlaybackInterval.subtitle(segment, offset: 0, padding: 1, duration: 10))
        #expect(low.start == 1)
        #expect(low.end == 2)
        #expect(abs(high.start - 0.7) <= 0.000_001)
        #expect(abs(high.end - 2.3) <= 0.000_001)
    }

    @Test func testBeginningEndAndOutsideVideo() throws {
        let beginning = try #require(PlaybackInterval.subtitle(segment, offset: -1, padding: 0.3, duration: 10))
        #expect(beginning.start == 0)
        let ending = try #require(PlaybackInterval.subtitle(segment, offset: 8, padding: 0.3, duration: 10))
        #expect(ending.end == 10)
        #expect(PlaybackInterval.subtitle(segment, offset: 20, padding: 0.3, duration: 10) == nil)
        #expect(PlaybackInterval.subtitle(segment, offset: -20, padding: 0.3, duration: 10) == nil)
        #expect(PlaybackInterval.subtitle(segment, offset: 0, padding: 0.3, duration: 0) == nil)
        #expect(PlaybackInterval.subtitle(segment, offset: .nan, padding: 0.3, duration: 10) == nil)
    }

    @Test func testABValidationAndArbitraryLength() throws {
        let bounds = try #require(PlaybackInterval.ab(a: 1.234, b: 6.789, duration: 10))
        #expect(bounds.start == 1.234)
        #expect(bounds.end == 6.789)
        #expect(PlaybackInterval.ab(a: 0, b: 10, duration: 10) != nil)
        #expect(PlaybackInterval.ab(a: nil, b: 2, duration: 10) == nil)
        #expect(PlaybackInterval.ab(a: 1, b: nil, duration: 10) == nil)
        #expect(PlaybackInterval.ab(a: 2, b: 2, duration: 10) == nil)
        #expect(PlaybackInterval.ab(a: 3, b: 2, duration: 10) == nil)
        #expect(PlaybackInterval.ab(a: -1, b: 2, duration: 10) == nil)
        #expect(PlaybackInterval.ab(a: 0, b: 11, duration: 10) == nil)
        #expect(PlaybackInterval.ab(a: .nan, b: 2, duration: 10) == nil)
        #expect(PlaybackInterval.ab(a: 1, b: .infinity, duration: 10) == nil)
    }

    @Test func testBoundaryDecisions() throws {
        let bounds = try #require(PlaybackInterval.ab(a: 1, b: 2, duration: 10))
        #expect(!(bounds.contains(0.999)))
        #expect(bounds.contains(1))
        #expect(bounds.contains(1.999))
        #expect(!(bounds.contains(2)))
        #expect(!(bounds.reachedEnd(at: 1.999)))
        #expect(bounds.reachedEnd(at: 2))
        #expect(bounds.reachedEnd(at: 2.1))
        #expect(!(bounds.reachedEnd(at: .nan)))
    }
}
