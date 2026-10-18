import Foundation

public enum StudyNote {
    public static func timestamp(_ time: Double) -> String {
        guard time.isFinite, time >= 0, time < Double(Int.max / 1_000 - 1) else { return "—" }
        let milliseconds = Int((time * 1_000).rounded())
        return String(format: "%02ld:%02ld:%02ld.%03ld", milliseconds / 3_600_000,
                      milliseconds / 60_000 % 60, milliseconds / 1_000 % 60, milliseconds % 1_000)
    }

    public static func videoLink(_ source: URL, start: Double) -> URL? {
        guard let host = source.host?.lowercased(),
              ["youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be", "www.youtu.be"].contains(host),
              start.isFinite, start >= 0, start < Double(Int.max / 1_000),
              var components = URLComponents(url: source, resolvingAgainstBaseURL: false) else { return nil }
        var items = (components.queryItems ?? []).filter { !["t", "start", "time_continue"].contains($0.name) }
        items.append(URLQueryItem(name: "t", value: "\(Int(start.rounded(.down)))s"))
        components.queryItems = items
        components.fragment = nil
        return components.url
    }

    public static func filename(sentence: String, date: Date = Date(), id: UUID = UUID()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let title = sentence.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return "\(formatter.string(from: date)) - \(title.prefix(70)) - \(id.uuidString.prefix(8)).md"
    }

    public static func markdown(selection: StudySelection, lesson: EnglishLesson, sourceName: String,
                                sourceURL: URL, model: String, playback: PlaybackInterval?) -> String {
        func number(_ value: Double) -> String { String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value) }
        func quote(_ text: String) -> String { text.components(separatedBy: .newlines).map { "> " + $0 }.joined(separator: "\n") }
        let start = playback?.start ?? selection.startTime, end = playback?.end ?? selection.endTime
        var lines = ["# English Shadowing", "", "- 来源：\(sourceName.replacingOccurrences(of: "\n", with: " "))",
                     "- 时间线：\(timestamp(start)) → \(timestamp(end))",
                     "- 字幕范围：\(number(selection.startTime))–\(number(selection.endTime)) 秒",
                     "- 模型：\(model)"]
        lines.append("- [视频原链接](<\(sourceURL.absoluteString)>)")
        if let link = videoLink(sourceURL, start: start) {
            lines.append("- [从 \(timestamp(start)) 开始播放](<\(link.absoluteString)>)")
        }
        if let playback { lines.append("- 播放范围（含偏移和留白）：\(number(playback.start))–\(number(playback.end)) 秒") }
        if selection.timingIsEstimated { lines.append("- 句界在字幕内部：时间按文字比例估算，请回听核对。") }
        lines += ["", "## 原句", "", quote(selection.sentence), "", "## 中文意思", "", lesson.translation,
                  "", "## 这句话怎么听懂", "", lesson.listening.strategy, "", "## 按意群听", ""]
        for chunk in lesson.listening.chunks { lines += [quote(chunk.english), "", chunk.meaning, ""] }
        lines += ["## 语音与听辨难点", "", "以下是基于文字推测的常见读法，需回听核对；没有分析这段音频。", ""]
        for change in lesson.listening.soundChanges { lines += ["### \(change.excerpt)", "", change.explanation, ""] }
        lines += ["## 回听练习", "", lesson.listening.drill, "", "## 句法补充", "", lesson.structure, "", "## 实用表达", ""]
        for phrase in lesson.phrases { lines += ["### \(phrase.phrase)", "", phrase.explanation, "", quote(phrase.example), ""] }
        lines += ["## 换个说法练一练", ""]
        for practice in lesson.practice { lines += [quote(practice.english), "", practice.chinese, ""] }
        lines += ["## 自测", "", lesson.question, "", "## 参考答案", "", lesson.answer, ""]
        return lines.joined(separator: "\n")
    }
}
