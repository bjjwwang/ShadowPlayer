import Foundation
import CryptoKit
#if SWIFT_PACKAGE
import ShadowingCore
#endif

struct CachedLesson: Codable, Sendable {
    let version: Int
    let text: String
    let model: String
    let createdAt: Date
    let lesson: EnglishLesson

    init(text: String, model: String, lesson: EnglishLesson) {
        version = 1
        self.text = LessonCache.normalized(text)
        self.model = model
        createdAt = Date()
        self.lesson = lesson
    }
}

struct LessonCache: Sendable {
    let directory: URL
    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Shadowing Player/Lessons", isDirectory: true)) {
        self.directory = directory
    }

    static func normalized(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    func file(for text: String) -> URL {
        let digest = SHA256.hash(data: Data(Self.normalized(text).utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".json")
    }

    func read(text: String) throws -> CachedLesson? {
        let data: Data
        do { data = try Data(contentsOf: file(for: text)) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(CachedLesson.self, from: data)
        guard entry.version == 1, entry.text == Self.normalized(text) else { throw CocoaError(.fileReadCorruptFile) }
        return entry
    }

    func save(_ entry: CachedLesson) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(entry).write(to: file(for: entry.text), options: .atomic)
    }
}
