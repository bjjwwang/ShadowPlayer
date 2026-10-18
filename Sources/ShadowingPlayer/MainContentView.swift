import SwiftUI
import AVFoundation
#if SWIFT_PACKAGE
import ShadowingCore
#endif

struct MainContentView: View {
    @ObservedObject var controller: PlayerController
    @State private var showHelp = false
    @State private var showYouTube = false
    @State private var showStudy = false
    @State private var studyGeneration = -1
    @State private var studySourceName = ""
    @State private var studySourceURL: URL?
    @StateObject private var youtube = YouTubeLoader()
    @StateObject private var study = EnglishStudyController()
    @State private var scrubbing = false
    @State private var scrubTime = 0.0

    var body: some View {
        VSplitView {
            VStack(spacing: 10) {
                NativeVideoView(player: controller.player)
                    .frame(minHeight: 160)
                    .overlay {
                        if controller.player.currentItem == nil {
                            Text("Open a local MP4 or MOV to begin").foregroundStyle(.white.opacity(0.7))
                        }
                    }
                transport
                practice
            }
            .padding([.horizontal, .bottom], 12)
            .frame(minHeight: 300)
            TranscriptView(controller: controller, onStudy: learn).frame(minHeight: 180)
        }
        .background(KeyboardRouter(controller: controller))
        .toolbar {
            ToolbarItemGroup {
                Button("Open Video…", action: controller.openVideo)
                Button("Import SRT…", action: controller.importSubtitles)
                Button("YouTube…") { showYouTube = true }
                Button("学习当前句") {
                    if let id = controller.activeID ?? controller.selectedID,
                       let segment = controller.timeline.segments.first(where: { $0.id == id }) { learn(segment) }
                }.disabled(controller.timeline.segments.isEmpty)
                Button { showStudy = true } label: {
                    Label(study.isChecking ? "Codex 检测中…" : (study.isLoggedIn ? "Codex 已登录" : "Codex 未连接"),
                          systemImage: study.isLoggedIn ? "checkmark.circle" : "person.crop.circle")
                }.help(study.status)
                Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }
                    .help("Keyboard shortcuts and timing controls")
            }
        }
        .navigationTitle("Shadowing Player")
        .navigationSubtitle(controller.videoName)
        .alert("Unable to complete action", isPresented: Binding(
            get: { controller.errorMessage != nil },
            set: { if !$0 { controller.errorMessage = nil } }
        )) {
            Button("OK") { controller.errorMessage = nil }
        } message: { Text(controller.errorMessage ?? "") }
        .sheet(isPresented: $showHelp) { help }
        .sheet(isPresented: $showYouTube, onDismiss: youtube.cancel) {
            YouTubeImportView(loader: youtube, controller: controller) { showYouTube = false }
        }
        .sheet(isPresented: $showStudy, onDismiss: study.cancel) {
            EnglishStudyView(study: study, player: controller, sourceGeneration: studyGeneration,
                             sourceName: studySourceName, sourceURL: studySourceURL) { showStudy = false }
        }
        .task { study.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            youtube.cancel()
            study.cancel()
            controller.removeYouTubeCache()
        }
    }

    private func learn(_ segment: SubtitleSegment) {
        controller.pause()
        controller.stopStudy()
        controller.selectedID = segment.id
        studyGeneration = controller.contentGeneration
        studySourceName = controller.videoName
        studySourceURL = controller.sourceURL
        showStudy = true
        study.learn(segments: controller.timeline.segments, focusID: segment.id)
    }

    private var transport: some View {
        HStack(spacing: 12) {
            Button(action: controller.togglePlayback) {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill").frame(width: 18)
            }.help("Play / pause (Space)")
            Button { controller.seekRelative(-5) } label: { Image(systemName: "gobackward.5") }.help("Back 5 seconds (←)")
            Button { controller.seekRelative(5) } label: { Image(systemName: "goforward.5") }.help("Forward 5 seconds (→)")
            Slider(value: Binding(
                get: { scrubbing ? scrubTime : controller.currentTime },
                set: { scrubTime = $0; scrubbing = true }
            ), in: 0...max(0.001, controller.duration), onEditingChanged: { editing in
                if !editing { controller.seek(to: scrubTime); scrubbing = false }
            }).accessibilityLabel("Playback position")
            Text("\(PlayerController.timeLabel(scrubbing ? scrubTime : controller.currentTime)) / \(PlayerController.timeLabel(controller.duration))")
                .monospacedDigit().font(.system(.caption, design: .monospaced)).fixedSize()
            Picker("Speed", selection: $controller.speed) {
                Text("0.75×").tag(Float(0.75))
                Text("1.0×").tag(Float(1))
                Text("1.25×").tag(Float(1.25))
            }.frame(width: 115)
        }.disabled(!controller.isReady)
    }

    private var practice: some View {
        HStack(spacing: 10) {
            Button { controller.navigateSubtitle(-1) } label: { Image(systemName: "backward.end") }.help("Previous subtitle (↑)")
            Button { controller.playSelected(repeating: controller.repeatSentence) } label: { Text("Play sentence") }
                .disabled(!controller.isReady || (controller.selectedID ?? controller.activeID) == nil)
            Toggle("Repeat", isOn: $controller.repeatSentence).toggleStyle(.checkbox)
                .onChange(of: controller.repeatSentence) { _, repeating in
                    if case .subtitle = controller.mode { controller.playSelected(repeating: repeating) }
                }
            Button { controller.navigateSubtitle(1) } label: { Image(systemName: "forward.end") }.help("Next subtitle (↓)")
            Divider().frame(height: 18)
            Button("Set A", action: controller.markA).help("Mark current position (A)")
            Button("Set B", action: controller.markB).help("Mark current position (B)")
            Button(controller.mode == .ab ? "Stop A–B loop" : "Loop A–B", action: controller.toggleAB).help("Toggle A–B loop (L)")
            Button("Replay A–B", action: controller.replayAB)
            Spacer(minLength: 0)
            if controller.mode != nil {
                Button("Exit practice", action: controller.clearPractice).help("Exit active practice mode (Esc)")
            }
        }
        .controlSize(.small)
        .disabled(!controller.isReady)
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Shadowing Player Help").font(.title2)
            Text("Click a transcript entry to seek, then use Play sentence to practise it. Repeat loops the sentence; turn it off to play once. R repeats the selected sentence.")
            Text("YouTube… accepts a public video link, retrieves existing English captions, and caches the video for native playback. Creator captions are preferred over automatic captions. Loading needs an internet connection.")
            Text("每条字幕旁的“学习”会暂停视频，从听力角度讲解这句话：拆意群、抓关键词、解释可能的弱读和连读，再简要补充句法。语音提示基于文字，需要回听核对。顶部显示 Codex 登录状态；默认使用可用的轻量模型，需要联网并消耗 Codex 额度。")
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
                shortcut("Space", "Play / pause")
                shortcut("← / →", "Seek backward / forward 5 seconds")
                shortcut("↑ / ↓", "Select previous / next subtitle")
                shortcut("R", "Repeat selected subtitle")
                shortcut("A / B", "Mark interval start / end")
                shortcut("L", "Toggle A–B loop")
                shortcut("Esc", "Exit active practice mode")
                shortcut("⌘O / ⇧⌘O", "Open video / import SRT")
            }
            Text("Positive offset makes subtitles later; negative offset makes them earlier. Padding adds up to 300 ms on each side of a sentence. A–B markers use video time and are independent of subtitle offset.")
            Text("The transcript follows playback automatically. Manual scrolling temporarily pauses follow; it resumes after two seconds without scrolling. Starting playback or sentence practice also resumes follow. Seeking exits practice mode; the selected entry and A–B markers remain available.")
            Button("Done") { showHelp = false }.keyboardShortcut(.defaultAction)
        }.padding(24).frame(width: 550)
    }

    private func shortcut(_ key: String, _ description: String) -> some View {
        GridRow { Text(key).font(.system(.body, design: .monospaced)); Text(description) }
    }
}

struct TranscriptView: View {
    @ObservedObject var controller: PlayerController
    var onStudy: (SubtitleSegment) -> Void
    @State private var followResumeTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transcript").font(.headline)
                Spacer()
                Text("Offset (s)")
                TextField("Seconds", value: $controller.offset, format: .number.precision(.fractionLength(3)))
                    .frame(width: 75).textFieldStyle(.roundedBorder).accessibilityLabel("Subtitle offset in seconds")
                Stepper("", value: $controller.offset, step: 0.05).labelsHidden().help("Adjust offset by 50 ms")
                Picker("Padding", selection: $controller.padding) {
                    Text("0 ms").tag(0.0)
                    Text("100 ms").tag(0.1)
                    Text("150 ms").tag(0.15)
                    Text("200 ms").tag(0.2)
                    Text("300 ms").tag(0.3)
                }.frame(width: 150)
                Button(controller.followsTranscript ? "Following" : (followResumeTask != nil ? "Auto-resuming…" : "Follow playback")) {
                    followResumeTask?.cancel()
                    followResumeTask = nil
                    controller.followsTranscript.toggle()
                }.help("Enable or suspend automatic transcript scrolling")
            }.padding(12)
            HStack {
                Text(controller.subtitleStatus).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("A \(controller.markerA.map(PlayerController.timeLabel) ?? "—")   B \(controller.markerB.map(PlayerController.timeLabel) ?? "—")").monospacedDigit()
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 8)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(controller.timeline.segments) { segment in
                            row(segment).id(segment.id)
                        }
                    }.padding(10)
                    if controller.timeline.segments.isEmpty {
                        Text("Import UTF-8 SRT subtitles to see a time-aligned transcript here.")
                            .foregroundStyle(.secondary).padding(24)
                    }
                }
                .background(TranscriptScrollMonitor {
                    guard controller.followsTranscript || followResumeTask != nil else { return }
                    controller.followsTranscript = false
                    followResumeTask?.cancel()
                    followResumeTask = Task { @MainActor in
                        do { try await Task.sleep(for: .seconds(2)) }
                        catch { return }
                        controller.followsTranscript = true
                        followResumeTask = nil
                    }
                })
                .onChange(of: controller.activeID) { _, id in
                    if controller.followsTranscript, let id { proxy.scrollTo(id, anchor: .center) }
                }
                .onChange(of: controller.followsTranscript) { _, follows in
                    if follows {
                        followResumeTask?.cancel()
                        followResumeTask = nil
                        if let id = controller.activeID { proxy.scrollTo(id, anchor: .center) }
                    }
                }
                .onChange(of: controller.isPlaying) { _, playing in
                    if playing, controller.followsTranscript, let id = controller.activeID {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
                .onDisappear { followResumeTask?.cancel(); followResumeTask = nil }
            }
        }
    }

    private func row(_ segment: SubtitleSegment) -> some View {
        let active = controller.activeID == segment.id
        let selected = controller.selectedID == segment.id
        return HStack(spacing: 8) {
            Button {
                NSApp.keyWindow?.makeFirstResponder(nil)
                controller.selectSubtitle(segment)
            } label: {
                HStack(alignment: .top, spacing: 14) {
                    Text("\(PlayerController.timeLabel(segment.startTime))\n\(PlayerController.timeLabel(segment.endTime))")
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
                    Text(segment.text).frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.primary).multilineTextAlignment(.leading)
                }
                .padding(10)
                .background(active ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.accentColor : .clear, lineWidth: 1))
                .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(segment.text), at \(PlayerController.timeLabel(segment.startTime))")
            Button("学习") { onStudy(segment) }
                .controlSize(.small).help("用 Codex 学习这句话或附近几句")
        }
    }
}

// AVPlayerLayer renders native video without a caption overlay or a second transport owner.
struct NativeVideoView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> VideoSurface { VideoSurface(player: player) }
    func updateNSView(_ view: VideoSurface, context: Context) { view.videoLayer.player = player }
}

final class VideoSurface: NSView {
    let videoLayer = AVPlayerLayer()
    init(player: AVPlayer) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        videoLayer.player = player
        videoLayer.videoGravity = .resizeAspect
        layer?.addSublayer(videoLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
    }
}
