import Foundation

public struct PlaybackInterval: Equatable, Sendable {
    public let start: Double
    public let end: Double

    public static func subtitle(_ segment: SubtitleSegment, offset: Double, padding: Double, duration: Double) -> Self? {
        guard offset.isFinite, padding.isFinite, duration.isFinite, duration > 0,
              segment.startTime.isFinite, segment.endTime.isFinite, segment.endTime > segment.startTime else { return nil }
        let padding = min(0.3, max(0, padding))
        return bounded(start: segment.startTime + offset - padding,
                       end: segment.endTime + offset + padding, duration: duration)
    }

    public static func ab(a: Double?, b: Double?, duration: Double) -> Self? {
        guard let a, let b, a.isFinite, b.isFinite, a >= 0, a < b, b <= duration else { return nil }
        return bounded(start: a, end: b, duration: duration)
    }

    private static func bounded(start: Double, end: Double, duration: Double) -> Self? {
        guard duration.isFinite, duration > 0 else { return nil }
        let start = max(0, min(duration, start)), end = max(0, min(duration, end))
        guard end > start else { return nil }
        return Self(start: start, end: end)
    }

    public func reachedEnd(at time: Double) -> Bool { time.isFinite && time >= end }
    public func contains(_ time: Double) -> Bool { time >= start && time < end }
}
