import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import ShadowingCore
#endif
@testable import ShadowingPlayer

private actor GenerationCount {
    private(set) var value = 0
    func increment() { value += 1 }
}

struct LessonCacheTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("study-cache-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func lesson() throws -> EnglishLesson {
        try JSONDecoder().decode(EnglishLesson.self, from: Data("""
        {"translation":"仔细听。","structure":"祈使句。","phrases":[],
         "listening":{"strategy":"抓 listen。","chunks":[{"english":"Listen carefully.","meaning":"仔细听"}],
           "soundChanges":[],"drill":"原速复听。"},"practice":[],"question":"做什么？","answer":"仔细听。"}
        """.utf8))
    }

    private func connection() throws -> CodexConnection {
        let models = try JSONDecoder().decode([StudyModel].self, from: Data("""
        [{"model":"first-mini","displayName":"First","defaultReasoningEffort":"low","supportedReasoningEfforts":[{"reasoningEffort":"low"}]},
         {"model":"second-mini","displayName":"Second","defaultReasoningEffort":"low","supportedReasoningEfforts":[{"reasoningEffort":"low"}]}]
        """.utf8))
        return CodexConnection(login: .chatGPT, models: models)
    }

    @MainActor private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(condition())
    }

    @Test func filesSurviveNewCacheInstancesAndUseStableNormalizedTextKeys() throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = LessonCache(directory: directory), fixture = try lesson()
        #expect(try cache.read(text: "Not studied") == nil)
        try cache.save(CachedLesson(text: "Café.\nListen carefully.", model: "old-model", lesson: fixture))
        let reopened = LessonCache(directory: directory)
        let restored = try #require(try reopened.read(text: "  Cafe\u{301}.  Listen carefully.  "))
        #expect(restored.lesson == fixture && restored.model == "old-model")
        #expect(cache.file(for: "Café. Listen carefully.") == reopened.file(for: "Cafe\u{301}.\nListen carefully."))
        #expect(cache.file(for: "Different text.") != cache.file(for: "Café. Listen carefully."))
    }

    @Test @MainActor
    func repeatedClicksRestartAndModelChangesReuseLessonsWithoutGenerating() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = LessonCache(directory: directory), fixture = try lesson(), login = try connection()
        let count = GenerationCount()
        let controller = EnglishStudyController(cache: cache, connect: { login }, generate: { _, _ in
            await count.increment()
            try await Task.sleep(for: .milliseconds(30))
            return fixture
        })
        controller.refresh()
        try await waitUntil { !controller.isChecking }
        let cue = SubtitleSegment(id: 1, startTime: 1, endTime: 3, text: "Listen carefully.")
        for _ in 0..<8 { controller.learn(segments: [cue], focusID: cue.id) }
        try await waitUntil { controller.lesson != nil }
        #expect(await count.value == 1)
        controller.modelID = "second-mini"
        controller.relearn()
        #expect(controller.lesson == fixture && controller.lessonModel == "first-mini")
        #expect(await count.value == 1)

        // A fresh controller has no login/models at all; it must still load disk cache.
        let reopened = EnglishStudyController(cache: LessonCache(directory: directory), generate: { _, _ in
            await count.increment(); return fixture
        })
        let later = SubtitleSegment(id: 99, startTime: 61, endTime: 63, text: cue.text)
        reopened.learn(segments: [later], focusID: later.id)
        #expect(!reopened.isLoggedIn && reopened.lesson == fixture)
        #expect(reopened.selection?.startTime == 61)
        #expect(reopened.cacheStatus.contains("不消耗"))
        #expect(await count.value == 1)

        controller.relearn(regenerate: true)
        try await waitUntil { !controller.isLearning }
        #expect(await count.value == 2)
        #expect(try cache.read(text: cue.text)?.model == "second-mini")
    }

    @Test @MainActor
    func damagedCacheDoesNotSilentlySpendTokens() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = LessonCache(directory: directory), fixture = try lesson(), login = try connection()
        let cue = SubtitleSegment(id: 1, startTime: 1, endTime: 3, text: "Listen carefully.")
        let count = GenerationCount()
        try Data("broken cache".utf8).write(to: cache.file(for: cue.text))
        let controller = EnglishStudyController(cache: cache, connect: { login }, generate: { _, _ in
            await count.increment(); return fixture
        })
        controller.refresh()
        try await waitUntil { !controller.isChecking }
        controller.learn(segments: [cue], focusID: cue.id)
        #expect(controller.error != nil && controller.lesson == nil && !controller.isLearning)
        #expect(await count.value == 0)
        controller.relearn(regenerate: true)
        try await waitUntil { !controller.isLearning }
        #expect(await count.value == 1)
        #expect(try cache.read(text: cue.text)?.lesson == fixture)
    }

    @Test @MainActor
    func failedDiskSaveKeepsMemoryAndCanRetryWithoutAnotherGeneration() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocked = directory.appendingPathComponent("Lessons"), cache = LessonCache(directory: directory.appendingPathComponent("Lessons"))
        let fixture = try lesson(), login = try connection(), count = GenerationCount()
        let controller = EnglishStudyController(cache: cache, connect: { login }, generate: { _, _ in
            await count.increment()
            // Make the previously absent cache directory unwritable after the cache miss.
            try Data("file blocking the cache directory".utf8).write(to: blocked)
            return fixture
        })
        controller.refresh()
        try await waitUntil { !controller.isChecking }
        let cue = SubtitleSegment(id: 1, startTime: 1, endTime: 3, text: "Listen carefully.")
        controller.learn(segments: [cue], focusID: cue.id)
        try await waitUntil { !controller.isLearning }
        #expect(controller.cacheSaveFailed && controller.lesson == fixture)
        controller.relearn()
        #expect(controller.cacheSaveFailed && controller.lesson == fixture)
        #expect(await count.value == 1)
        try FileManager.default.removeItem(at: blocked)
        controller.retryCacheSave()
        #expect(!controller.cacheSaveFailed)
        #expect(try cache.read(text: cue.text)?.lesson == fixture)
        #expect(await count.value == 1)
    }
}
