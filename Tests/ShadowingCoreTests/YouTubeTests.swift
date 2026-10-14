import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import ShadowingCore
#else
@testable import ShadowingPlayer
#endif

struct YouTubeTests {
    @Test func acceptedLinksCanonicalizeToOneVideo() throws {
        for link in ["https://www.youtube.com/watch?v=Y6bbMQXQ180&t=30&list=abc", "https://youtu.be/Y6bbMQXQ180?si=abc",
                     "youtube.com/shorts/Y6bbMQXQ180", "https://m.youtube.com/watch?v=Y6bbMQXQ180",
                     "http://youtube.com/embed/Y6bbMQXQ180", "https://youtube.com/live/Y6bbMQXQ180"] {
            #expect(try YouTubeLink.canonicalURL(link).absoluteString == "https://www.youtube.com/watch?v=Y6bbMQXQ180")
        }
    }

    @Test func invalidHostsAndArgumentsRejected() {
        for link in ["https://youtube.com.evil.example/watch?v=Y6bbMQXQ180", "https://evil.example/Y6bbMQXQ180",
                     "https://user:pass@youtube.com/watch?v=Y6bbMQXQ180", "file:///tmp/video.mp4", "--exec evil",
                     "https://youtube.com/playlist?list=abc", "https://youtu.be/short", "https://youtube.com:443/watch?v=Y6bbMQXQ180",
                     "https://youtu.be/Y6bbMQXQ180/extra", "https://youtube.com/watch?v=abcdefghij!", ""] {
            #expect(throws: YouTubeError.self) { try YouTubeLink.canonicalURL(link) }
        }
    }

    private func metadata(_ extra: String) throws -> YouTubeMetadata {
        try JSONDecoder().decode(YouTubeMetadata.self, from: Data("{\"id\":\"Y6bbMQXQ180\",\"title\":\"Video\",\"duration\":180,\(extra)}".utf8))
    }

    @Test func manualEnglishPreferredOverAutomatic() throws {
        let meta = try metadata("\"subtitles\":{\"en-GB\":[{\"ext\":\"json3\"}],\"fr\":[{\"ext\":\"json3\"}]},\"automatic_captions\":{\"en\":[{\"ext\":\"json3\"}]}")
        #expect(meta.englishCaption?.language == "en-GB")
        #expect(meta.englishCaption?.automatic == false)
        #expect(meta.isSupported)
    }

    @Test func originalAutomaticEnglishPreferredAndMissingEnglishHandled() throws {
        let meta = try metadata("\"automatic_captions\":{\"en\":[{\"ext\":\"json3\"}],\"en-orig\":[{\"ext\":\"json3\"}]}")
        #expect(meta.englishCaption?.language == "en-orig")
        #expect(meta.englishCaption?.automatic == true)
        #expect(try metadata("\"subtitles\":{\"fr\":[{\"ext\":\"json3\"}]}").englishCaption == nil)
        #expect(try metadata("\"subtitles\":{\"en\":[{\"ext\":\"vtt\"}]}").englishCaption == nil)
    }

    @Test func liveAndRestrictedVideoRejected() throws {
        #expect(!(try metadata("\"is_live\":true").isSupported))
        #expect(!(try metadata("\"live_status\":\"is_upcoming\"").isSupported))
        #expect(!(try metadata("\"availability\":\"private\"").isSupported))
        #expect(!(try metadata("\"availability\":\"needs_auth\"").isSupported))
        #expect(try metadata("\"availability\":\"unlisted\",\"live_status\":\"was_live\"").isSupported)
    }

    @Test func timedTextMultilineMillisecondsAndEmptyEvents() throws {
        let data = Data(#"{"events":[{"tStartMs":1234,"dDurationMs":2345,"segs":[{"utf8":"Hello "},{"utf8":"world\nSecond line"}]},{"tStartMs":0,"dDurationMs":100,"segs":[{"utf8":"\n"}]},{"tStartMs":5,"segs":[{"utf8":"No duration"}]},{"tStartMs":10,"dDurationMs":0,"segs":[{"utf8":"Empty range"}]}]}"#.utf8)
        let segments = try YouTubeCaptionParser.parse(data)
        #expect(segments.count == 1)
        #expect(segments[0].startTime == 1.234)
        #expect(segments[0].endTime == 3.579)
        #expect(segments[0].text == "Hello world\nSecond line")
    }

    @Test func automaticDisplayOverlapClippedButManualTimesPreserved() throws {
        let data = Data(#"{"events":[{"tStartMs":1000,"dDurationMs":6000,"segs":[{"utf8":"First"}]},{"tStartMs":3000,"dDurationMs":1000,"segs":[{"utf8":"Second"}]}]}"#.utf8)
        #expect(try YouTubeCaptionParser.parse(data)[0].endTime == 7)
        let automatic = try YouTubeCaptionParser.parse(data, automatic: true)
        #expect(automatic[0].endTime == 3)
        #expect(automatic[1].endTime == 4)
    }

    @Test func appendEventsMergedAndEmptyOrMalformedPayloadsHandled() throws {
        let data = Data(#"{"events":[{"tStartMs":1000,"dDurationMs":2000,"segs":[{"utf8":"Hello"}]},{"tStartMs":2000,"dDurationMs":2000,"aAppend":1,"segs":[{"utf8":" world"}]}]}"#.utf8)
        let segments = try YouTubeCaptionParser.parse(data)
        #expect(segments.count == 1)
        #expect(segments[0].text == "Hello world")
        #expect(segments[0].startTime == 1 && segments[0].endTime == 4)
        #expect(try YouTubeCaptionParser.parse(Data("{}".utf8)).isEmpty)
        #expect(throws: (any Error).self) { try YouTubeCaptionParser.parse(Data("broken".utf8)) }
    }
}
