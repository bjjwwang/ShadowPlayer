import Foundation
import Combine
import AVFoundation
#if SWIFT_PACKAGE
import ShadowingCore
#endif

struct YouTubeImport: Sendable {
    let directory: URL
    let video: URL
    let title: String
    let captions: [SubtitleSegment]
    let captionLabel: String
    var sourceURL: URL? = nil
}

enum YouTubeFetcher {
    static func executable(_ name: String, toolsDirectory: URL? = nil) -> URL? {
        let bundled = toolsDirectory ?? Bundle.main.resourceURL?.appendingPathComponent("Tools", isDirectory: true)
        if let bundled, FileManager.default.fileExists(atPath: bundled.path) {
            let tool = bundled.appendingPathComponent(name)
            // A standalone bundle never silently depends on tools installed on this Mac.
            return FileManager.default.isExecutableFile(atPath: tool.path) ? tool : nil
        }
        let directories = [NSHomeDirectory() + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] +
            (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":")
        return directories.lazy.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func fetch(_ url: URL, directory requestedDirectory: URL? = nil, toolsDirectory: URL? = nil,
                      progress: @escaping @Sendable (String) -> Void) async throws -> YouTubeImport {
        try Task.checkCancellation()
        guard let tool = executable("yt-dlp", toolsDirectory: toolsDirectory) else { throw YouTubeError.missingTool }
        let directory = requestedDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("ShadowingYouTube-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var handedOff = false
        defer { if !handedOff { try? FileManager.default.removeItem(at: directory) } }
        var common = ["--ignore-config", "--no-plugin-dirs", "--no-playlist", "--no-cache-dir", "--no-colors",
                      "--socket-timeout", "20", "--retries", "1", "--extractor-retries", "1", "--no-progress"]
        if let deno = executable("deno", toolsDirectory: toolsDirectory) { common += ["--js-runtimes", "deno:\(deno.path)"] }
        else if let node = executable("node", toolsDirectory: toolsDirectory) { common += ["--js-runtimes", "node:\(node.path)"] }
        else { throw YouTubeError.missingTool }
        let runner = YouTubeToolProcess()
        progress("Checking video and English captions…")
        let metadataData = try await runner.run(tool, arguments: common + ["--skip-download", "--dump-single-json", "--", url.absoluteString], directory: directory)
        let metadata = try JSONDecoder().decode(YouTubeMetadata.self, from: metadataData)
        guard metadata.isSupported else { throw YouTubeError.unsupportedVideo }
        guard let choice = metadata.englishCaption else { throw YouTubeError.missingCaptions }
        try Task.checkCancellation()

        progress("Getting \(choice.automatic ? "automatic" : "creator") English captions…")
        let template = directory.appendingPathComponent("video.%(ext)s").path
        let subtitleArgs = ["--skip-download", choice.automatic ? "--write-auto-subs" : "--write-subs",
                            "--sub-langs", choice.language, "--sub-format", "json3", "-o", template, "--", url.absoluteString]
        _ = try await runner.run(tool, arguments: common + subtitleArgs, directory: directory)
        let captionURL = directory.appendingPathComponent("video.\(choice.language).json3")
        let captions = try YouTubeCaptionParser.parse(Data(contentsOf: captionURL), automatic: choice.automatic)
        guard !captions.isEmpty else { throw YouTubeError.invalidCaptions }
        try Task.checkCancellation()

        progress("Caching video for native playback… This can take a few minutes.")
        // Retrieve H.264/AAC tracks without invoking an external media merger.
        let combined = "b[ext=mp4][vcodec^=avc1][acodec^=mp4a]"
        let format = "bv[height<=720][ext=mp4][vcodec^=avc1]+ba[ext=m4a]/" + combined
        _ = try await runner.run(tool, arguments: common + ["-f", format, "-o", template,
            "--ffmpeg-location", directory.path, "--fixup", "never", "--", url.absoluteString], directory: directory)
        try Task.checkCancellation()
        let video = directory.appendingPathComponent("video.mp4")
        if !FileManager.default.fileExists(atPath: video.path) {
            progress("Preparing video for native playback…")
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            guard let videoTrack = files.first(where: { $0.lastPathComponent.hasPrefix("video.f") && $0.pathExtension == "mp4" }),
                  let audioTrack = files.first(where: { $0.lastPathComponent.hasPrefix("video.f") && $0.pathExtension == "m4a" }) else {
                throw YouTubeError.retrieval("No compatible H.264/AAC video was available. Choose another video.")
            }
            try await NativeMediaMerger.merge(video: videoTrack, audio: audioTrack, output: video)
            try? FileManager.default.removeItem(at: videoTrack)
            try? FileManager.default.removeItem(at: audioTrack)
        }
        handedOff = true
        return YouTubeImport(directory: directory, video: video, title: metadata.title,
                             captions: captions, captionLabel: choice.label, sourceURL: url)
    }
}

// Run off the main actor; file-backed output avoids pipe deadlocks for large metadata.
// Cancellation terminates the active yt-dlp process and prevents later import stages.
final class YouTubeToolProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    private func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let process, process.isRunning { process.terminate() }
    }

    func run(_ executable: URL, arguments: [String], directory: URL) async throws -> Data {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { [self] in
                    let result: Result<Data, any Error> = Result {
                        let output = directory.appendingPathComponent("output-\(UUID()).log")
                        let errors = directory.appendingPathComponent("errors-\(UUID()).log")
                        FileManager.default.createFile(atPath: output.path, contents: nil)
                        FileManager.default.createFile(atPath: errors.path, contents: nil)
                        defer { try? FileManager.default.removeItem(at: output); try? FileManager.default.removeItem(at: errors) }
                        let outHandle = try FileHandle(forWritingTo: output)
                        let errHandle = try FileHandle(forWritingTo: errors)
                        defer { try? outHandle.close(); try? errHandle.close() }
                        let child = Process()
                        child.executableURL = executable; child.arguments = arguments
                        child.standardOutput = outHandle; child.standardError = errHandle
                        child.standardInput = FileHandle.nullDevice
                        child.currentDirectoryURL = directory
                        var environment = ProcessInfo.processInfo.environment
                        environment["PATH"] = [executable.deletingLastPathComponent().path, "/usr/bin", "/bin"].joined(separator: ":")
                        child.environment = environment
                        try start(child)
                        child.waitUntilExit()
                        try finish()
                        if child.terminationStatus != 0 {
                            let detail = String(decoding: try Data(contentsOf: errors), as: UTF8.self)
                            throw YouTubeError.retrieval(String(detail.suffix(2_000)).trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        return try Data(contentsOf: output)
                    }
                    // Finish cleanup before waking the caller; the next stage may remove the directory.
                    continuation.resume(with: result)
                }
            }
        } onCancel: { self.cancel() }
    }

    private func start(_ child: Process) throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        try child.run()
        process = child
    }

    private func finish() throws {
        lock.lock(); defer { lock.unlock() }
        process = nil
        if cancelled { throw CancellationError() }
    }
}

enum NativeMediaMerger {
    static func merge(video: URL, audio: URL, output: URL) async throws {
        try Task.checkCancellation()
        let videoAsset = AVURLAsset(url: video), audioAsset = AVURLAsset(url: audio)
        guard let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first,
              let sourceAudio = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw YouTubeError.retrieval("Downloaded media was missing an audio or video track.")
        }
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw YouTubeError.retrieval("Could not prepare the downloaded media tracks.")
        }
        let videoRange = try await sourceVideo.load(.timeRange), audioRange = try await sourceAudio.load(.timeRange)
        try videoTrack.insertTimeRange(videoRange, of: sourceVideo, at: .zero)
        try audioTrack.insertTimeRange(audioRange, of: sourceAudio, at: .zero)
        videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw YouTubeError.retrieval("Could not create the native MP4 exporter.")
        }
        // Passthrough remuxing keeps the downloaded H.264/AAC streams without re-encoding.
        if #available(macOS 15, *) {
            try await exporter.export(to: output, as: .mp4)
        } else {
            exporter.outputURL = output
            exporter.outputFileType = .mp4
            await exporter.export()
            if exporter.status != .completed {
                throw exporter.error ?? YouTubeError.retrieval("The native MP4 export did not finish.")
            }
        }
        try Task.checkCancellation()
    }
}

@MainActor
final class YouTubeLoader: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var status = ""
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?
    private var generation = 0
    private var workingDirectory: URL?

    func load(_ input: String, into controller: PlayerController, onLoaded: @escaping () -> Void) {
        guard !isLoading else { return }
        let url: URL
        do { url = try YouTubeLink.canonicalURL(input) }
        catch { self.error = error.localizedDescription; return }
        generation += 1
        let token = generation, contentToken = controller.contentGeneration
        isLoading = true; error = nil; status = "Connecting to YouTube…"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShadowingYouTube-\(UUID())", isDirectory: true)
        workingDirectory = directory
        task = Task { [weak self] in
            do {
                let result = try await YouTubeFetcher.fetch(url, directory: directory) { [weak self] status in
                    Task { @MainActor [weak self] in
                        if let self, self.generation == token { self.status = status }
                    }
                }
                guard let self, self.generation == token, !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: result.directory); return
                }
                guard controller.contentGeneration == contentToken else {
                    try? FileManager.default.removeItem(at: result.directory)
                    self.isLoading = false; self.status = "Cancelled because another video or transcript was opened."
                    self.workingDirectory = nil; self.task = nil
                    return
                }
                controller.installYouTube(result)
                self.workingDirectory = nil
                self.isLoading = false; self.status = "Ready"; self.task = nil
                onLoaded()
            } catch {
                guard let self, self.generation == token else { return }
                self.isLoading = false; self.task = nil
                self.workingDirectory = nil
                if error is CancellationError { self.status = "Cancelled" }
                else { self.error = error.localizedDescription; self.status = "" }
            }
        }
    }

    func cancel() {
        generation += 1; task?.cancel(); task = nil
        if let workingDirectory { try? FileManager.default.removeItem(at: workingDirectory) }
        workingDirectory = nil
        isLoading = false; status = "Cancelled"
    }
    isolated deinit { cancel() }
}
