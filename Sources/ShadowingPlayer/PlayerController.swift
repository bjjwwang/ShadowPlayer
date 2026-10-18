import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import ShadowingCore
#endif

@MainActor
final class PlayerController: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var timeline = SubtitleTimeline(segments: [])
    @Published private(set) var activeID: Int?
    @Published var selectedID: Int?
    @Published private(set) var currentTime = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var isPlaying = false
    @Published private(set) var isReady = false
    @Published private(set) var videoName = "Open a local video"
    @Published private(set) var subtitleStatus = "Import an SRT transcript"
    @Published var errorMessage: String?
    @Published var speed: Float = 1 { didSet { if desiredPlaying && !seeking { player.rate = speed } } }
    @Published var offset = 0.0 { didSet { timingChanged() } }
    @Published var padding = 0.15 { didSet { timingChanged() } }
    @Published var repeatSentence = true
    @Published private(set) var markerA: Double?
    @Published private(set) var markerB: Double?
    @Published private(set) var mode: PracticeMode?
    @Published var followsTranscript = true
    private(set) var contentGeneration = 0
    private(set) var sourceURL: URL?
    private var youtubeDirectory: URL?

    enum PracticeMode: Equatable {
        case subtitle(Int, repeating: Bool)
        case study(SubtitleSegment, repeating: Bool)
        case ab
    }
    private struct SeekRequest { let time: Double }
    private var periodicObserver: Any?
    private var boundaryObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var interval: PlaybackInterval?
    private var desiredPlaying = false
    private var seeking = false
    private var queuedSeek: SeekRequest?
    private var seekDestination: Double?
    private var generation = 0
    private var boundaryGeneration = 0
    private var subtitleImportGeneration = 0
    private var videoURL: URL?
    private var hasVideoScope = false

    init() {
        player.appliesMediaSelectionCriteriaAutomatically = false
        periodicObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.04, preferredTimescale: 1_000), queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in self?.observe(time.seconds) }
        }
    }

    isolated deinit {
        if let periodicObserver { player.removeTimeObserver(periodicObserver) }
        if let boundaryObserver { player.removeTimeObserver(boundaryObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        statusObserver?.invalidate()
        if hasVideoScope { videoURL?.stopAccessingSecurityScopedResource() }
        if let youtubeDirectory { try? FileManager.default.removeItem(at: youtubeDirectory) }
    }

    func openVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video, .audiovisualContent]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadVideo(url)
    }

    func loadVideo(_ url: URL) {
        contentGeneration += 1
        generation += 1
        let token = generation
        player.pause()
        player.currentItem?.cancelPendingSeeks()
        clearPractice()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        statusObserver?.invalidate()
        if hasVideoScope { videoURL?.stopAccessingSecurityScopedResource() }
        videoURL = url
        sourceURL = url
        hasVideoScope = url.startAccessingSecurityScopedResource()
        desiredPlaying = false; isPlaying = false; seeking = false; queuedSeek = nil; seekDestination = nil
        duration = 0; currentTime = 0; isReady = false; activeID = nil; selectedID = nil
        markerA = nil; markerB = nil
        videoName = url.lastPathComponent
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        if let youtubeDirectory { try? FileManager.default.removeItem(at: youtubeDirectory) }
        youtubeDirectory = nil
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.handleStatus(token: token)
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, !self.seeking else { return }
                let time = self.player.currentTime().seconds
                // A queued end notification may arrive after an internal seek has already wrapped.
                if let interval = self.interval, self.desiredPlaying, interval.reachedEnd(at: time) {
                    self.finishInterval()
                } else if time >= self.duration {
                    self.pause(); self.observe(time)
                }
            }
        }
        Task { [weak self] in
            do {
                let duration = try await item.asset.load(.duration).seconds
                // Explicitly disable embedded subtitle/caption tracks as well as keeping SRT separate.
                if let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) {
                    item.select(nil, in: group)
                }
                guard let self, self.generation == token else { return }
                guard duration.isFinite, duration > 0 else {
                    self.errorMessage = "This file has no finite playable duration. Choose a local video supported by AVFoundation."
                    return
                }
                self.duration = duration
                self.handleStatus(token: token)
            } catch {
                guard let self, self.generation == token else { return }
                self.errorMessage = "Could not open this video: \(error.localizedDescription). Try an MP4 or MOV with H.264/HEVC video and AAC audio."
            }
        }
    }

    private func handleStatus(token: Int) {
        guard generation == token, let item = player.currentItem else { return }
        if item.status == .failed {
            isReady = false; pause()
            errorMessage = "AVFoundation could not play this file. \(item.error?.localizedDescription ?? "The codec may be unsupported.") Try an MP4 or MOV with H.264/HEVC video and AAC audio."
        } else if item.status == .readyToPlay && duration > 0 {
            isReady = true
            updateActive(at: player.currentTime().seconds)
        }
    }

    func importSubtitles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText, .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadSubtitles(url)
    }

    func loadSubtitles(_ url: URL) {
        contentGeneration += 1
        subtitleImportGeneration += 1
        let token = subtitleImportGeneration
        subtitleStatus = "Reading \(url.lastPathComponent)…"
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    guard let text = String(data: data, encoding: .utf8) else {
                        throw CocoaError(.fileReadInapplicableStringEncoding)
                    }
                    return SubtitleParser.parse(text)
                }.value
                guard subtitleImportGeneration == token else { return }
                switch mode {
                case .subtitle, .study: pause(); clearPractice()
                default: break
                }
                timeline = SubtitleTimeline(segments: result.segments)
                contentGeneration += 1
                selectedID = nil
                updateActive(at: player.currentTime().seconds)
                subtitleStatus = "\(url.lastPathComponent) · \(result.segments.count) entries" +
                    (result.skippedEntries > 0 ? " · \(result.skippedEntries) malformed entries skipped" : "")
                if result.segments.isEmpty { subtitleStatus += " · No usable subtitles" }
            } catch {
                guard subtitleImportGeneration == token else { return }
                subtitleStatus = "Subtitle import failed"
                errorMessage = "Could not read the subtitles as UTF-8 SRT: \(error.localizedDescription)"
            }
        }
    }

    func installYouTube(_ result: YouTubeImport) {
        loadVideo(result.video)
        youtubeDirectory = result.directory
        videoName = "YouTube · \(result.title)"
        sourceURL = result.sourceURL
        subtitleImportGeneration += 1
        offset = 0
        timeline = SubtitleTimeline(segments: result.captions)
        subtitleStatus = "\(result.captionLabel) · \(result.captions.count) entries"
        followsTranscript = true
        updateActive(at: player.currentTime().seconds)
    }

    func removeYouTubeCache() {
        if let youtubeDirectory {
            pause()
            player.replaceCurrentItem(with: nil)
            try? FileManager.default.removeItem(at: youtubeDirectory)
            self.youtubeDirectory = nil
        }
    }

    private func observe(_ time: Double) {
        guard !seeking, time.isFinite else { return }
        currentTime = max(0, time)
        updateActive(at: time)
        isPlaying = player.rate != 0
        if desiredPlaying, let interval, interval.reachedEnd(at: time) { finishInterval() }
    }

    private func updateActive(at time: Double) {
        let id = timeline.activeID(at: time, offset: offset)
        if activeID != id { activeID = id }
    }

    func togglePlayback() {
        guard isReady else { return }
        if desiredPlaying { pause(); return }
        followsTranscript = true
        desiredPlaying = true
        if seeking { return }
        let time = player.currentTime().seconds
        if let interval, !interval.contains(time) { enqueueSeek(interval.start) }
        else if time >= duration { enqueueSeek(0) }
        else { player.rate = speed; isPlaying = true }
    }

    func pause() { desiredPlaying = false; player.pause(); isPlaying = false }

    // Explicit user seeks exit practice mode, so loop boundaries never fight scrubbing.
    func seek(to time: Double) {
        guard isReady else { return }
        clearPractice()
        enqueueSeek(time)
    }

    func seekRelative(_ delta: Double) {
        seek(to: (queuedSeek?.time ?? seekDestination ?? player.currentTime().seconds) + delta)
    }

    private func enqueueSeek(_ time: Double) {
        guard isReady, time.isFinite else { return }
        let request = SeekRequest(time: max(0, min(duration, time)))
        if seeking { queuedSeek = request; return }
        performSeek(request)
    }

    private func performSeek(_ request: SeekRequest) {
        seeking = true
        seekDestination = request.time
        player.pause(); isPlaying = false
        let token = generation
        player.seek(to: CMTime(seconds: request.time, preferredTimescale: 1_000_000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.seeking = false
                self.seekDestination = nil
                if let next = self.queuedSeek {
                    self.queuedSeek = nil
                    self.performSeek(next)
                    return
                }
                self.observe(self.player.currentTime().seconds)
                if finished && self.desiredPlaying && !self.seeking {
                    self.player.rate = self.speed; self.isPlaying = true
                } else if !finished { self.pause() }
            }
        }
    }

    func selectSubtitle(_ segment: SubtitleSegment) {
        selectedID = segment.id
        seek(to: segment.startTime + offset)
    }

    func navigateSubtitle(_ delta: Int) {
        let segments = timeline.segments
        guard !segments.isEmpty else { return }
        let index = segments.firstIndex { $0.id == (selectedID ?? activeID) }
        let next = index.map { min(segments.count - 1, max(0, $0 + delta)) } ?? (delta > 0 ? 0 : segments.count - 1)
        selectSubtitle(segments[next])
    }

    func playSelected(repeating: Bool) {
        guard isReady, let id = selectedID ?? activeID,
              let segment = timeline.segments.first(where: { $0.id == id }) else { return }
        guard let bounds = PlaybackInterval.subtitle(segment, offset: offset, padding: padding, duration: duration) else {
            errorMessage = "This subtitle is outside the video after applying the offset."
            return
        }
        selectedID = id
        followsTranscript = true
        mode = .subtitle(id, repeating: repeating)
        installInterval(bounds)
        desiredPlaying = true
        enqueueSeek(bounds.start)
    }

    func playStudy(_ segment: SubtitleSegment, contentGeneration token: Int, repeating: Bool) {
        guard contentGeneration == token, isReady,
              let bounds = PlaybackInterval.subtitle(segment, offset: offset, padding: padding, duration: duration) else { return }
        selectedID = segment.id
        followsTranscript = true
        mode = .study(segment, repeating: repeating)
        installInterval(bounds)
        desiredPlaying = true
        enqueueSeek(bounds.start)
    }

    func stopStudy() {
        if case .study = mode { pause(); clearPractice() }
    }

    func markA() {
        guard isReady else { return }
        if mode == .ab { clearPractice() }
        markerA = max(0, min(duration, player.currentTime().seconds))
        if let b = markerB, b <= markerA! { markerB = nil }
    }

    func markB() {
        guard isReady else { return }
        if mode == .ab { clearPractice() }
        let time = max(0, min(duration, player.currentTime().seconds))
        guard let a = markerA, time > a else {
            errorMessage = "Set A first, then set B at a later playback position."
            return
        }
        markerB = time
    }

    func toggleAB() {
        if mode == .ab { clearPractice(); return }
        replayAB()
    }

    func replayAB() {
        guard isReady else { return }
        guard let bounds = PlaybackInterval.ab(a: markerA, b: markerB, duration: duration) else {
            errorMessage = "Set valid A and B markers with A earlier than B."
            return
        }
        mode = .ab
        followsTranscript = true
        installInterval(bounds)
        desiredPlaying = true
        enqueueSeek(bounds.start)
    }

    func clearPractice() {
        mode = nil; interval = nil
        boundaryGeneration += 1
        if let boundaryObserver { player.removeTimeObserver(boundaryObserver) }
        boundaryObserver = nil
    }

    private func installInterval(_ bounds: PlaybackInterval) {
        if let boundaryObserver { player.removeTimeObserver(boundaryObserver) }
        interval = bounds
        boundaryGeneration += 1
        let token = boundaryGeneration
        boundaryObserver = player.addBoundaryTimeObserver(forTimes: [NSValue(time: CMTime(seconds: bounds.end, preferredTimescale: 1_000_000))], queue: .main) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.boundaryGeneration == token, !self.seeking, self.desiredPlaying,
                      self.player.currentTime().seconds >= bounds.end else { return }
                self.finishInterval()
            }
        }
    }

    private func finishInterval() {
        guard !seeking, desiredPlaying, let interval, let mode else { return }
        switch mode {
        case .ab, .subtitle(_, repeating: true), .study(_, repeating: true): enqueueSeek(interval.start)
        case .subtitle(_, repeating: false), .study(_, repeating: false):
            pause()
            enqueueSeek(interval.end)
        }
    }

    private func timingChanged() {
        updateActive(at: player.currentTime().seconds)
        let segment: SubtitleSegment
        switch mode {
        case .subtitle(let id, _):
            guard let found = timeline.segments.first(where: { $0.id == id }) else { return }
            segment = found
        case .study(let source, _): segment = source
        default: return
        }
        guard let bounds = PlaybackInterval.subtitle(segment, offset: offset, padding: padding, duration: duration) else {
            pause(); clearPractice(); return
        }
        installInterval(bounds)
        if seeking || !bounds.contains(player.currentTime().seconds) { enqueueSeek(bounds.start) }
    }

    static func timeLabel(_ time: Double) -> String {
        guard time.isFinite else { return "00:00.000" }
        let milliseconds = Int(max(0, time) * 1_000)
        let seconds = milliseconds / 1_000
        if seconds >= 3_600 {
            return String(format: "%d:%02d:%02d.%03d", seconds / 3_600, seconds / 60 % 60, seconds % 60, milliseconds % 1_000)
        }
        return String(format: "%02d:%02d.%03d", seconds / 60, seconds % 60, milliseconds % 1_000)
    }
}
