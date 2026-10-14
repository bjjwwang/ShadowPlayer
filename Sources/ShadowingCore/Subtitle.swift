import Foundation

public struct SubtitleSegment: Identifiable, Equatable, Sendable {
    public let id: Int
    public let startTime: Double
    public let endTime: Double
    public let text: String

    public init(id: Int, startTime: Double, endTime: Double, text: String) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}

public struct SubtitleParseResult: Sendable {
    public let segments: [SubtitleSegment]
    public let skippedEntries: Int
}

public enum SubtitleParser {
    // Integer milliseconds avoid losing precision while parsing the source timestamps.
    public static func timestamp(_ string: String) -> Double? {
        let parts = string.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count >= 2, parts[1].count == 2 else { return nil }
        let seconds = parts[2].split(separator: ",", omittingEmptySubsequences: false)
        guard seconds.count == 2, seconds[0].count == 2, seconds[1].count == 3 else { return nil }
        let fields = [String(parts[0]), String(parts[1]), String(seconds[0]), String(seconds[1])]
        guard fields.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let hours = Int64(fields[0]), hours <= 1_000_000,
              let minutes = Int64(fields[1]), minutes < 60,
              let secs = Int64(fields[2]), secs < 60,
              let millis = Int64(fields[3]) else { return nil }
        return Double(((hours * 60 + minutes) * 60 + secs) * 1_000 + millis) / 1_000
    }

    public static func parse(_ input: String) -> SubtitleParseResult {
        let normalized = input.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var blocks: [[String]] = []
        var block: [String] = []
        for line in normalized.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !block.isEmpty { blocks.append(block); block = [] }
            } else { block.append(line) }
        }
        if !block.isEmpty { blocks.append(block) }
        var segments: [SubtitleSegment] = []
        var skipped = 0
        for (ordinal, lines) in blocks.enumerated() {
            // Accept an omitted numeric index; IDs remain unique even for duplicate source indices.
            let timingIndex = lines[0].contains("-->") ? 0 : 1
            guard lines.count > timingIndex + 1,
                  timingIndex == 0 || Int(lines[0].trimmingCharacters(in: .whitespaces)) != nil else {
                skipped += 1; continue
            }
            let times = lines[timingIndex].components(separatedBy: "-->")
            guard times.count == 2, let start = timestamp(times[0]), let end = timestamp(times[1]), end > start else {
                skipped += 1; continue
            }
            let text = lines[(timingIndex + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { skipped += 1; continue }
            segments.append(SubtitleSegment(id: ordinal, startTime: start, endTime: end, text: text))
        }
        segments.sort {
            if $0.startTime != $1.startTime { return $0.startTime < $1.startTime }
            return $0.id < $1.id
        }
        return SubtitleParseResult(segments: segments, skippedEntries: skipped)
    }
}

public struct SubtitleTimeline: Sendable {
    public let segments: [SubtitleSegment]
    private let prefixEnd: [Double]

    public init(segments: [SubtitleSegment]) {
        self.segments = segments.sorted {
            $0.startTime == $1.startTime ? $0.id < $1.id : $0.startTime < $1.startTime
        }
        var maxEnd = -Double.infinity
        prefixEnd = self.segments.map { maxEnd = max(maxEnd, $0.endTime); return maxEnd }
    }

    // Half-open intervals [start, end). Overlaps choose the latest start, then highest ID.
    // If that entry ends first, an earlier overlapping entry becomes active again.
    public func activeID(at videoTime: Double, offset: Double) -> Int? {
        guard videoTime.isFinite, offset.isFinite else { return nil }
        let time = videoTime - offset
        var low = 0, high = segments.count
        while low < high {
            let mid = (low + high) / 2
            if segments[mid].startTime <= time { low = mid + 1 } else { high = mid }
        }
        var index = low - 1
        while index >= 0 {
            if prefixEnd[index] <= time { return nil }
            let segment = segments[index]
            if segment.endTime > time { return segment.id }
            index -= 1
        }
        return nil
    }
}
