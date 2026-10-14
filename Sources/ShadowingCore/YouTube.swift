import Foundation

public enum YouTubeError: LocalizedError, Sendable {
    case invalidURL, missingTool, unsupportedVideo, missingCaptions, invalidCaptions
    case retrieval(String)
    public var errorDescription: String? {
        switch self {
        case .invalidURL: "Paste a valid YouTube watch, Shorts, or youtu.be video link."
        case .missingTool: "The YouTube tools are missing or incomplete. Re-copy the standalone app, or see README for developer setup instructions."
        case .unsupportedVideo: "Choose a public, recorded YouTube video. Live streams, private videos, and videos requiring sign-in are not supported."
        case .missingCaptions: "This video has no usable English captions. Choose another video or open a local video and import your own SRT."
        case .invalidCaptions: "The English caption track was empty or could not be parsed. Try another video or import an SRT file."
        case .retrieval(let detail): "YouTube could not be loaded. \(detail)"
        }
    }
}

public enum YouTubeLink {
    public static func canonicalURL(_ input: String) throws -> URL {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard let url = URLComponents(string: text),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              url.user == nil, url.password == nil, url.port == nil,
              let host = url.host?.lowercased() else { throw YouTubeError.invalidURL }
        let path = url.path.split(separator: "/").map(String.init)
        let id: String?
        if host == "youtu.be", path.count == 1 { id = path.first }
        else if ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"].contains(host) {
            if url.path == "/watch" { id = url.queryItems?.first(where: { $0.name == "v" })?.value }
            else if path.count == 2, ["shorts", "embed", "live"].contains(path[0]) { id = path[1] }
            else { id = nil }
        } else { id = nil }
        guard let id, id.utf8.count == 11,
              id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw YouTubeError.invalidURL
        }
        return URL(string: "https://www.youtube.com/watch?v=\(id)")!
    }
}

public struct YouTubeMetadata: Decodable, Sendable {
    public struct CaptionFormat: Decodable, Sendable { public let ext: String }
    public struct CaptionChoice: Equatable, Sendable {
        public let language: String
        public let automatic: Bool
        public var label: String { "\(automatic ? "YouTube automatic" : "Creator") English captions (\(language))" }
    }
    public let id: String
    public let title: String
    public let duration: Double?
    public let is_live: Bool?
    public let live_status: String?
    public let availability: String?
    public let subtitles: [String: [CaptionFormat]]?
    public let automatic_captions: [String: [CaptionFormat]]?

    public var isSupported: Bool {
        guard is_live != true, !["is_live", "is_upcoming", "post_live"].contains(live_status ?? ""),
              let duration, duration.isFinite, duration > 0 else { return false }
        return availability == nil || ["public", "unlisted"].contains(availability ?? "")
    }

    public var englishCaption: CaptionChoice? {
        for (tracks, automatic) in [(subtitles, false), (automatic_captions, true)] {
            let languages = (tracks ?? [:]).keys.filter {
                ($0 == "en" || $0.hasPrefix("en-")) && $0.utf8.allSatisfy {
                    (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
                }
            }
                .sorted {
                    func priority(_ code: String) -> Int { code == "en-orig" ? 0 : code == "en" ? 1 : 2 }
                    return priority($0) == priority($1) ? $0 < $1 : priority($0) < priority($1)
                }
            for language in languages where tracks?[language]?.contains(where: { $0.ext == "json3" }) == true {
                return CaptionChoice(language: language, automatic: automatic)
            }
        }
        return nil
    }
}

public enum YouTubeCaptionParser {
    private struct Document: Decodable { let events: [Event]? }
    private struct Event: Decodable {
        let tStartMs: Double?
        let dDurationMs: Double?
        let aAppend: Int?
        let segs: [TextPart]?
    }
    private struct TextPart: Decodable { let utf8: String? }

    // JSON3 carries full timed utterances, avoiding duplicated rolling WebVTT cue windows.
    public static func parse(_ data: Data, automatic: Bool = false) throws -> [SubtitleSegment] {
        let document = try JSONDecoder().decode(Document.self, from: data)
        var result: [SubtitleSegment] = []
        for (id, event) in (document.events ?? []).enumerated() {
            guard let startMs = event.tStartMs, let durationMs = event.dDurationMs,
                  startMs.isFinite, startMs >= 0, durationMs.isFinite, durationMs > 0 else { continue }
            let text = (event.segs ?? []).compactMap(\.utf8).joined()
                .replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let start = startMs / 1_000, end = (startMs + durationMs) / 1_000
            guard end.isFinite else { continue }
            if event.aAppend == 1, let previous = result.last, start <= previous.endTime {
                result[result.count - 1] = SubtitleSegment(id: previous.id, startTime: previous.startTime,
                    endTime: max(end, previous.endTime), text: previous.text + " " + text)
            } else {
                result.append(SubtitleSegment(id: id, startTime: start, endTime: end, text: text))
            }
        }
        result.sort { $0.startTime == $1.startTime ? $0.id < $1.id : $0.startTime < $1.startTime }
        // Auto-caption durations can include lingering display time over the next utterance.
        // Clip that overlap for practice; manual captions retain their source bounds.
        if automatic, result.count > 1 {
            for index in 0..<(result.count - 1) {
                let current = result[index], next = result[index + 1]
                if next.startTime > current.startTime, current.endTime > next.startTime {
                    result[index] = SubtitleSegment(id: current.id, startTime: current.startTime,
                        endTime: next.startTime, text: current.text)
                }
            }
        }
        return result
    }
}
