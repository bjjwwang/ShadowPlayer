import Foundation
import Testing
@testable import ShadowingPlayer
#if SWIFT_PACKAGE
import ShadowingCore
#endif

struct YouTubeLoaderTests {
    @Test func bundledToolsTakePriorityAndNeverFallBackToHostTools() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shadowing-tools-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(YouTubeFetcher.executable("yt-dlp", toolsDirectory: directory) == nil)
        let fakeTool = directory.appendingPathComponent("yt-dlp")
        try Data("test fixture".utf8).write(to: fakeTool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeTool.path)
        #expect(YouTubeFetcher.executable("yt-dlp", toolsDirectory: directory) == fakeTool)
        #expect(YouTubeFetcher.executable("node", toolsDirectory: directory) == nil)
    }

    @Test func subprocessUsesLiteralArgumentsAndCleansLogs() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shadowing-process-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try await YouTubeToolProcess().run(URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["%s", "$(untrusted); `argument`"], directory: directory)
        #expect(String(decoding: result, as: UTF8.self) == "$(untrusted); `argument`")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        await #expect(throws: (any Error).self) {
            try await YouTubeToolProcess().run(URL(fileURLWithPath: "/usr/bin/false"), arguments: [], directory: directory)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func subprocessCancellationTerminatesWork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shadowing-cancel-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let task = Task {
            try await YouTubeToolProcess().run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], directory: directory)
        }
        try await Task.sleep(for: .milliseconds(100))
        let start = ContinuousClock.now
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(ContinuousClock.now - start < .seconds(2))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SHADOWING_TEST_YOUTUBE"] != nil))
    @MainActor
    func realYouTubeImportNativePlaybackAndCacheCleanup() async throws {
        let input = try #require(ProcessInfo.processInfo.environment["SHADOWING_TEST_YOUTUBE"])
        let tools = ProcessInfo.processInfo.environment["SHADOWING_TEST_TOOLS"].map { URL(fileURLWithPath: $0) }
        let result = try await YouTubeFetcher.fetch(YouTubeLink.canonicalURL(input), toolsDirectory: tools) { _ in }
        defer { try? FileManager.default.removeItem(at: result.directory) }
        #expect(!result.captions.isEmpty)
        #expect(result.captions.allSatisfy { $0.endTime > $0.startTime })
        let controller = PlayerController()
        controller.offset = 1
        controller.installYouTube(result)
        let deadline = ContinuousClock.now + .seconds(15)
        while !controller.isReady && controller.errorMessage == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(controller.isReady, Comment(rawValue: controller.errorMessage ?? "Video not ready"))
        #expect(controller.videoName.hasPrefix("YouTube · "))
        #expect(controller.timeline.segments.count == result.captions.count)
        #expect(controller.offset == 0)
        let segment = try #require(result.captions.first { $0.startTime >= 0 && $0.endTime < controller.duration })
        controller.selectSubtitle(segment)
        let seekDeadline = ContinuousClock.now + .seconds(10)
        while abs(controller.currentTime - segment.startTime) > 0.01 && ContinuousClock.now < seekDeadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(abs(controller.currentTime - segment.startTime) < 0.01)
        #expect(controller.activeID == segment.id)
        controller.playSelected(repeating: true)
        let playDeadline = ContinuousClock.now + .seconds(5)
        while !controller.isPlaying && ContinuousClock.now < playDeadline { try await Task.sleep(for: .milliseconds(25)) }
        #expect(controller.isPlaying)
        controller.pause()
        controller.loadVideo(URL(fileURLWithPath: "/tmp/nonexistent-shadowing-fixture.mp4"))
        #expect(!FileManager.default.fileExists(atPath: result.directory.path))
    }
}
