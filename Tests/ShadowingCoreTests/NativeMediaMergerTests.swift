import AVFoundation
import Foundation
import Testing
@testable import ShadowingPlayer

struct NativeMediaMergerTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SHADOWING_TEST_VIDEO"] != nil))
    func remuxKeepsOneAudioAndVideoTrackAndDuration() async throws {
        let input = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["SHADOWING_TEST_VIDEO"]))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shadowing-mux-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("merged.mp4")
        try await NativeMediaMerger.merge(video: input, audio: input, output: output)
        let source = AVURLAsset(url: input), result = AVURLAsset(url: output)
        #expect(try await result.loadTracks(withMediaType: .video).count == 1)
        #expect(try await result.loadTracks(withMediaType: .audio).count == 1)
        let inputDuration = try await source.load(.duration).seconds
        let outputDuration = try await result.load(.duration).seconds
        #expect(abs(outputDuration - inputDuration) < 0.05)
    }
}
