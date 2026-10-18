import SwiftUI
#if SWIFT_PACKAGE
import ShadowingCore
#endif

struct EnglishStudyView: View {
    @ObservedObject var study: EnglishStudyController
    @ObservedObject var player: PlayerController
    let sourceGeneration: Int
    let sourceName: String
    let sourceURL: URL?
    var dismiss: () -> Void
    @State private var showAnswer = false
    @State private var rangeStart = 0.0
    @State private var rangeEnd = 0.0
    @StateObject private var obsidian = ObsidianExporter()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("学这段英语").font(.title2)
                Spacer()
                Button("完成", action: dismiss).keyboardShortcut(.cancelAction)
            }
            connectionControls
            playbackControls
            obsidianControls
            Text("仅将这段字幕发送给 Codex；需要联网，使用当前账户额度。默认选择可用的轻量模型及低推理档。")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            lessonContent
        }
        .padding(22).frame(width: 720, height: 660)
        .task { obsidian.refresh() }
        .onChange(of: study.scope) { _, _ in showAnswer = false; study.relearn() }
        .onChange(of: study.modelID) { _, _ in
            obsidian.resetSaved()
            if study.selection != nil, study.canLearn { showAnswer = false; study.relearn() }
        }
        .onChange(of: study.selection, initial: true) { _, selection in
            showAnswer = false
            player.stopStudy()
            rangeStart = selection?.startTime ?? 0
            rangeEnd = selection?.endTime ?? 0
            obsidian.resetSaved()
        }
        .onChange(of: study.lesson) { _, _ in obsidian.resetSaved() }
        .onChange(of: obsidian.vaultID) { _, _ in obsidian.resetSaved() }
        .onDisappear { player.stopStudy() }
    }

    private var playbackSegment: SubtitleSegment? {
        guard let selection = study.selection else { return nil }
        return SubtitleSegment(id: selection.focusID, startTime: rangeStart, endTime: rangeEnd, text: selection.sentence)
    }
    private var bounds: PlaybackInterval? {
        guard let segment = playbackSegment, sourceGeneration == player.contentGeneration, player.isReady else { return nil }
        return PlaybackInterval.subtitle(segment, offset: player.offset, padding: player.padding, duration: player.duration)
    }
    private var studyActive: Bool { if case .study = player.mode { true } else { false } }
    private var looping: Bool { if case .study(_, repeating: true) = player.mode { true } else { false } }

    private func play(repeating: Bool) {
        guard let segment = playbackSegment else { return }
        player.playStudy(segment, contentGeneration: sourceGeneration, repeating: repeating)
    }

    private var playbackControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("播放整句") { play(repeating: false) }.disabled(bounds == nil)
                Button(looping ? "停止循环" : "循环整句") {
                    if looping { player.stopStudy() } else { play(repeating: true) }
                }.disabled(bounds == nil && !looping)
                Button(player.isPlaying && studyActive ? "暂停" : "继续") { player.togglePlayback() }
                    .disabled(!studyActive)
                Picker("倍速", selection: $player.speed) {
                    Text("0.75×").tag(Float(0.75)); Text("1.0×").tag(Float(1)); Text("1.25×").tag(Float(1.25))
                }.frame(width: 125)
                Spacer(minLength: 0)
                Text(PlayerController.timeLabel(player.currentTime)).monospacedDigit().foregroundStyle(.secondary)
            }.controlSize(.small)
            if study.selection?.timingIsEstimated == true {
                Text("句界在同一条字幕中间，起止按文字比例估算；可展开微调，避免带入下一句。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("调整播放范围") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                      Text("字幕起点（秒）")
                      TextField("Start", value: $rangeStart, format: .number.precision(.fractionLength(3))).frame(width: 75)
                      Text("终点")
                      TextField("End", value: $rangeEnd, format: .number.precision(.fractionLength(3))).frame(width: 75)
                      Button("应用") {
                          let wasPlaying = studyActive && player.isPlaying, repeated = looping
                          player.stopStudy(); obsidian.resetSaved()
                          if wasPlaying { play(repeating: repeated) }
                      }.disabled(bounds == nil)
                      Spacer()
                    }
                    HStack {
                      Picker("留白", selection: $player.padding) {
                          Text("0 ms").tag(0.0); Text("100 ms").tag(0.1); Text("150 ms").tag(0.15)
                          Text("200 ms").tag(0.2); Text("300 ms").tag(0.3)
                      }.frame(width: 150)
                      Text("沿用当前字幕偏移").foregroundStyle(.secondary)
                    }
                }.textFieldStyle(.roundedBorder).controlSize(.small).padding(.top, 5)
            }.font(.caption)
            if study.selection != nil, bounds == nil {
                Text(player.isReady && sourceGeneration == player.contentGeneration ? "起点须早于终点，且范围需落在视频内。" : "打开原视频后可播放这句话；切换视频或字幕后，请重新选择学习内容。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var obsidianControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(obsidian.savedURL == nil ? "存入 Obsidian" : "已存入 Obsidian") {
                    guard let selection = study.selection, let lesson = study.lesson else { return }
                    let note = StudyNote.markdown(selection: selection, lesson: lesson, sourceName: sourceName,
                                                  sourceURL: sourceURL, model: study.modelID, playback: bounds)
                    obsidian.save(markdown: note, sentence: selection.sentence)
                }.disabled(study.lesson == nil || obsidian.selectedVault == nil || obsidian.savedURL != nil)
                    .help("保存到所选 vault 的 Shadowing Player 文件夹，不覆盖已有笔记")
                if obsidian.vaults.count > 1 {
                    Picker("库", selection: $obsidian.vaultID) {
                        ForEach(obsidian.vaults) { Text($0.name).tag($0.id) }
                    }.frame(maxWidth: 180)
                } else {
                    Text(obsidian.selectedVault?.name ?? "未检测到已配置的 vault").foregroundStyle(.secondary).lineLimit(1)
                }
                Button { obsidian.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("重新检测 Obsidian 配置")
                Spacer()
                if obsidian.savedURL != nil { Button("在 Obsidian 打开", action: obsidian.openSaved) }
            }.controlSize(.small)
            if let error = obsidian.error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }

    private var connectionControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(study.status, systemImage: study.isLoggedIn ? "checkmark.circle.fill" : "person.crop.circle")
                    .foregroundStyle(study.isLoggedIn ? Color.green : Color.secondary)
                Spacer()
                if study.isChecking { ProgressView().controlSize(.small) }
                Button("刷新登录状态", action: study.refresh).disabled(study.isChecking)
            }
            if !study.isLoggedIn {
                Text("请先在本机 Codex 桌面版或 CLI 中使用 ChatGPT 登录，再刷新。CLI 可运行 codex login。无需填写 API Key。")
                    .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            HStack {
                Picker("范围", selection: $study.scope) {
                    ForEach(StudyScope.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).frame(width: 200)
                    .help("这句话：定位字幕开头所属的句子，在句末截断。附近几句：另加前后一句。")
                Picker("模型", selection: $study.modelID) {
                    if study.modelID.isEmpty { Text("选择模型").tag("") }
                    ForEach(study.models) { Text($0.displayName).tag($0.id) }
                }.frame(maxWidth: .infinity)
                Button(study.isLearning ? "取消" : "讲解") {
                    if study.isLearning { study.cancel() } else { study.relearn() }
                }.disabled(!study.isLearning && (!study.canLearn || study.selection == nil))
            }
        }
    }

    private var lessonContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let selection = study.selection {
                    section("学习原文", selection.sentence)
                } else {
                    Text("点击任一字幕右侧的“学习”，或主窗口的“学习当前句”开始。")
                        .foregroundStyle(.secondary)
                }
                if study.isLearning { HStack { ProgressView().controlSize(.small); Text("Codex 正在讲解…") } }
                if let error = study.error { Text(error).foregroundStyle(.red) }
                if let lesson = study.lesson {
                    section("中文意思", lesson.translation)
                    listeningGuide(lesson.listening)
                    section("顺带看懂句法", lesson.structure)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("实用表达").font(.headline)
                        ForEach(Array(lesson.phrases.enumerated()), id: \.offset) { _, phrase in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(phrase.phrase).fontWeight(.medium)
                                Text(phrase.explanation)
                                Text(phrase.example).foregroundStyle(.secondary)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("换个说法练一练").font(.headline)
                        ForEach(Array(lesson.practice.enumerated()), id: \.offset) { _, practice in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(practice.english)
                                Text(practice.chinese).foregroundStyle(.secondary)
                            }
                        }
                    }
                    section("自测", lesson.question)
                    DisclosureGroup("查看答案", isExpanded: $showAnswer) { Text(lesson.answer).padding(.top, 6) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 8).textSelection(.enabled)
        }
    }

    private func listeningGuide(_ listening: EnglishLesson.Listening) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            section("这句话怎么听懂", listening.strategy)
            VStack(alignment: .leading, spacing: 8) {
                Text("按意群听，不逐词翻译").font(.headline)
                ForEach(Array(listening.chunks.enumerated()), id: \.offset) { _, chunk in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(chunk.english).fontWeight(.medium)
                        Text(chunk.meaning).foregroundStyle(.secondary)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("语音与听辨难点").font(.headline)
                Text("以下是基于文字推测的常见读法，需回听核对；没有分析这段音频。")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(listening.soundChanges.enumerated()), id: \.offset) { _, change in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(change.excerpt).fontWeight(.medium)
                        Text(change.explanation)
                    }
                }
            }
            section("回到视频这样练", listening.drill)
        }
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
