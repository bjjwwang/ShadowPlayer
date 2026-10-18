import SwiftUI
#if SWIFT_PACKAGE
import ShadowingCore
#endif

struct EnglishStudyView: View {
    @ObservedObject var study: EnglishStudyController
    var dismiss: () -> Void
    @State private var showAnswer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("学这段英语").font(.title2)
                Spacer()
                Button("完成", action: dismiss).keyboardShortcut(.cancelAction)
            }
            connectionControls
            Text("仅将这段字幕发送给 Codex；需要联网，使用当前账户额度。默认选择可用的轻量模型及低推理档。")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            lessonContent
        }
        .padding(22).frame(width: 680, height: 620)
        .onChange(of: study.scope) { _, _ in showAnswer = false; study.relearn() }
        .onChange(of: study.modelID) { _, _ in
            if study.selection != nil, study.canLearn { showAnswer = false; study.relearn() }
        }
        .onChange(of: study.selection) { _, _ in showAnswer = false }
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
