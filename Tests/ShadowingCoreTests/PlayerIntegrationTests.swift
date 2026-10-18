import Foundation
import Testing
#if SWIFT_PACKAGE
import ShadowingCore
#endif
@testable import ShadowingPlayer

// Optional AVFoundation smoke test. Point SHADOWING_TEST_VIDEO at a local >= 3-second video.
// This observes the real player; sleeps here only wait for asynchronous operations.
struct PlayerIntegrationTests {
    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(condition(), "Timed out waiting for AVPlayer")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SHADOWING_TEST_VIDEO"] != nil))
    @MainActor
    func realPlaybackSeekLoopRatePauseAndReplacement() async throws {
        let fixture = try #require(ProcessInfo.processInfo.environment["SHADOWING_TEST_VIDEO"])
        let controller = PlayerController()
        controller.player.isMuted = true
        let srt = FileManager.default.temporaryDirectory.appendingPathComponent("shadowing-test-\(UUID()).srt")
        defer { try? FileManager.default.removeItem(at: srt); controller.pause() }
        try "1\n00:00:00,400 --> 00:00:00,900\nFirst\n\n2\n00:00:01,100 --> 00:00:01,600\nSecond".write(to: srt, atomically: true, encoding: .utf8)
        controller.loadSubtitles(srt)
        try await waitUntil { controller.timeline.segments.count == 2 }
        controller.loadVideo(URL(fileURLWithPath: fixture))
        try await waitUntil { controller.isReady || controller.errorMessage != nil }
        try #require(controller.isReady, Comment(rawValue: controller.errorMessage ?? "Video not ready"))
        try #require(controller.duration >= 3)
        let first = controller.timeline.segments[0]
        let second = controller.timeline.segments[1]

        // Rapid transcript clicks must finish at the last destination.
        for _ in 0..<8 { controller.selectSubtitle(first); controller.selectSubtitle(second) }
        try await waitUntil { abs(controller.currentTime - 1.1) < 0.01 }
        #expect(controller.activeID == second.id)
        controller.offset = 0.2
        #expect(controller.activeID == nil)
        controller.offset = -0.2
        #expect(controller.activeID == second.id)
        controller.offset = 0

        if controller.duration >= 10 {
            controller.seek(to: 0)
            controller.seekRelative(5)
            controller.seekRelative(5)
            controller.seekRelative(-5)
            try await waitUntil { abs(controller.currentTime - 5) < 0.01 }
            #expect(!controller.isPlaying)
            controller.selectSubtitle(second)
            try await waitUntil { abs(controller.currentTime - 1.1) < 0.01 }
        }

        // Play-once must pause at the bounded end, preserving selected speed.
        controller.padding = 0
        controller.speed = 1.25
        controller.playSelected(repeating: false)
        try await waitUntil { controller.isPlaying }
        #expect(controller.player.rate == 1.25)
        try await waitUntil { !controller.isPlaying && abs(controller.currentTime - 1.6) < 0.01 }
        #expect(controller.activeID == nil)

        controller.speed = 0.75
        controller.playSelected(repeating: true)
        try await waitUntil { controller.isPlaying }
        var previous = controller.currentTime
        var wrapped = false
        let deadline = ContinuousClock.now + .seconds(4)
        while !wrapped && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
            let time = controller.currentTime
            if previous - time > 0.2 { wrapped = true }
            previous = time
        }
        #expect(wrapped)
        try await waitUntil { controller.isPlaying }
        #expect(controller.player.rate == 0.75)
        controller.pause()
        let paused = controller.player.currentTime().seconds
        try await Task.sleep(for: .milliseconds(150))
        #expect(abs(controller.player.currentTime().seconds - paused) < 0.01)

        // A-B markers use video timestamps; offset changes don't move them.
        controller.seek(to: 0.3)
        try await waitUntil { abs(controller.currentTime - 0.3) < 0.01 }
        #expect(controller.mode == nil)
        controller.markA()
        controller.seek(to: 0.8)
        try await waitUntil { abs(controller.currentTime - 0.8) < 0.01 }
        controller.markB()
        controller.replayAB()
        try await waitUntil { controller.isPlaying && controller.currentTime < 0.7 }
        #expect(controller.mode == .ab)
        controller.offset = 0.4
        #expect(abs((controller.markerA ?? -1) - 0.3) < 0.01)
        #expect(abs((controller.markerB ?? -1) - 0.8) < 0.01)
        previous = controller.currentTime; wrapped = false
        let abDeadline = ContinuousClock.now + .seconds(4)
        while !wrapped && ContinuousClock.now < abDeadline {
            try await Task.sleep(for: .milliseconds(25))
            let time = controller.currentTime
            if previous - time > 0.2 { wrapped = true }
            previous = time
        }
        #expect(wrapped)
        controller.seek(to: 2)
        try await waitUntil { abs(controller.currentTime - 2) < 0.1 }
        #expect(controller.mode == nil)
        controller.pause()

        // Exercise the boundary observer and end notification together at the physical file end.
        controller.seek(to: controller.duration - 0.4)
        try await waitUntil { abs(controller.currentTime - (controller.duration - 0.4)) < 0.01 }
        controller.markA()
        controller.seek(to: controller.duration)
        try await waitUntil { abs(controller.currentTime - controller.duration) < 0.01 }
        controller.markB()
        controller.speed = 1.25
        controller.replayAB()
        try await waitUntil { controller.isPlaying && controller.currentTime < controller.duration - 0.1 }
        previous = controller.currentTime
        var wraps = 0
        let endDeadline = ContinuousClock.now + .seconds(4)
        while wraps < 2 && ContinuousClock.now < endDeadline {
            try await Task.sleep(for: .milliseconds(20))
            let time = controller.currentTime
            if previous - time > 0.2 { wraps += 1 }
            previous = time
        }
        #expect(wraps >= 2)
        controller.pause()
        controller.clearPractice()
        controller.seek(to: controller.duration - 0.1)
        try await waitUntil { abs(controller.currentTime - (controller.duration - 0.1)) < 0.01 }
        controller.togglePlayback()
        try await waitUntil { !controller.isPlaying && controller.currentTime >= controller.duration - 0.01 }

        controller.loadVideo(URL(fileURLWithPath: fixture))
        #expect(controller.markerA == nil && controller.markerB == nil)
        #expect(controller.mode == nil && controller.selectedID == nil)
        try await waitUntil { controller.isReady }
        #expect(controller.currentTime == 0)
        #expect(!controller.isPlaying)
        #expect(controller.timeline.segments.count == 2)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SHADOWING_TEST_VIDEO"] != nil))
    @MainActor
    func studySentenceSpansCuesLoopsAndStopsWithoutStalePlayback() async throws {
        let fixture = try #require(ProcessInfo.processInfo.environment["SHADOWING_TEST_VIDEO"])
        let controller = PlayerController()
        controller.player.isMuted = true
        defer { controller.stopStudy(); controller.pause() }
        let srt = FileManager.default.temporaryDirectory.appendingPathComponent("shadowing-study-\(UUID()).srt")
        defer { try? FileManager.default.removeItem(at: srt) }
        try "1\n00:00:00,300 --> 00:00:00,600\nI think\n\n2\n00:00:00,600 --> 00:00:00,950\nwe need\n\n3\n00:00:00,950 --> 00:00:01,400\nto reconsider.".write(to: srt, atomically: true, encoding: .utf8)
        controller.loadSubtitles(srt)
        try await waitUntil { controller.timeline.segments.count == 3 }
        controller.loadVideo(URL(fileURLWithPath: fixture))
        try await waitUntil { controller.isReady }
        let selection = try #require(StudySelection(segments: controller.timeline.segments, focusID: controller.timeline.segments[1].id, scope: .sentence))
        let token = controller.contentGeneration
        #expect(selection.startTime == 0.3 && selection.endTime == 1.4)
        controller.padding = 0
        controller.speed = 1.25
        controller.playStudy(selection.playbackSegment, contentGeneration: token, repeating: false)
        try await waitUntil { controller.isPlaying }
        #expect(controller.player.rate == 1.25)
        try await waitUntil { !controller.isPlaying && abs(controller.currentTime - 1.4) < 0.01 }

        controller.speed = 0.75
        for _ in 0..<6 { controller.playStudy(selection.playbackSegment, contentGeneration: token, repeating: true) }
        try await waitUntil { controller.isPlaying }
        var previous = controller.currentTime, wrapped = false
        let deadline = ContinuousClock.now + .seconds(4)
        while !wrapped && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
            let now = controller.currentTime
            if previous - now > 0.4 { wrapped = true }
            previous = now
        }
        #expect(wrapped)
        controller.offset = 0.2
        controller.pause()
        controller.playStudy(selection.playbackSegment, contentGeneration: token, repeating: false)
        try await waitUntil { controller.isPlaying }
        #expect(controller.player.rate == 0.75)
        try await waitUntil { !controller.isPlaying && abs(controller.currentTime - 1.6) < 0.01 }
        controller.playStudy(selection.playbackSegment, contentGeneration: token, repeating: true)
        controller.stopStudy()
        try await Task.sleep(for: .milliseconds(150))
        #expect(controller.mode == nil && !controller.isPlaying)
        controller.loadVideo(URL(fileURLWithPath: fixture))
        try await waitUntil { controller.isReady }
        controller.playStudy(selection.playbackSegment, contentGeneration: token, repeating: true)
        #expect(controller.mode == nil && !controller.isPlaying)
    }
}
