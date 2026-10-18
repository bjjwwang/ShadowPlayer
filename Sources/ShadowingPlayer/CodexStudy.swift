import Foundation
import Combine
#if SWIFT_PACKAGE
import ShadowingCore
#endif

enum CodexStudyError: LocalizedError {
    case missing, signedOut, unsupportedAuth, noModel, timeout, failed(String)
    var errorDescription: String? {
        switch self {
        case .missing: "未找到本机 Codex。请先安装并登录 Codex 桌面版或 CLI，然后刷新状态。"
        case .signedOut: "本机 Codex 尚未登录。请在 Codex 中使用 ChatGPT 登录，然后刷新状态。"
        case .unsupportedAuth: "当前 Codex 使用的不是 ChatGPT 登录。此功能仅复用 ChatGPT 登录，不使用 API Key。"
        case .noModel: "未选择可用模型。请从模型列表中选择，或更新 Codex 后刷新并检查账户权限。"
        case .timeout: "Codex 响应超时，请稍后重试。"
        case .failed(let detail): "Codex 暂时无法完成请求。\(detail)"
        }
    }
}

struct CodexConnection: Sendable {
    enum Login: Sendable { case chatGPT, signedOut, other }
    let login: Login
    let models: [StudyModel]
}

enum CodexBridge {
    static func executable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let desktopPaths = ["/Applications", home + "/Applications"].flatMap { folder in
            ["Codex.app", "ChatGPT.app"].flatMap { name in
                ["codex", "codex-cli/bin/codex", "codex-cli/CodexCLI.app/Contents/MacOS/codex"].map {
                    folder + "/" + name + "/Contents/Resources/" + $0
                }
            }
        }
        let candidates = [home + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"] + desktopPaths +
            (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/codex" }
        return candidates.map { URL(fileURLWithPath: $0) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func connection() async throws -> CodexConnection {
        guard let cli = executable() else { throw CodexStudyError.missing }
        return try await CodexJob().run(timeout: 25) { job in
            let input = Pipe(), output = Pipe()
            try job.start(cli, arguments: ["app-server", "--listen", "stdio://"],
                          input: input, output: output, error: FileHandle.nullDevice)
            defer { try? input.fileHandleForWriting.close() }
            func send(_ method: String, _ params: [String: Any], id: Int? = nil) throws {
                var message: [String: Any] = ["method": method, "params": params]
                if let id { message["id"] = id }
                var data = try JSONSerialization.data(withJSONObject: message)
                data.append(10)
                try input.fileHandleForWriting.write(contentsOf: data)
            }
            try send("initialize", ["clientInfo": ["name": "shadowing_player", "version": "1.3.0"]], id: 1)
            var login: CodexConnection.Login?, models: [StudyModel]?
            var buffer = Data()
            while login == nil || models == nil {
                let chunk = output.fileHandleForReading.availableData
                if chunk.isEmpty { throw CodexStudyError.failed("请更新 Codex 后重试。") }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 10) {
                    let line = buffer.prefix(upTo: newline)
                    buffer.removeSubrange(...newline)
                    guard let message = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                    if message["error"] != nil { throw CodexStudyError.failed("本机 Codex 接口不可用，请更新 Codex 后重试。") }
                    guard let id = message["id"] as? Int, let result = message["result"] as? [String: Any] else { continue }
                    switch id {
                    case 1:
                        try send("initialized", [:])
                        try send("account/read", ["refreshToken": false], id: 2)
                        try send("model/list", ["limit": 100, "includeHidden": false], id: 3)
                    case 2:
                        let account = result["account"] as? [String: Any]
                        login = account == nil ? .signedOut : (account?["type"] as? String == "chatgpt" ? .chatGPT : .other)
                        if login != .chatGPT { return CodexConnection(login: login!, models: []) }
                    case 3:
                        let data = try JSONSerialization.data(withJSONObject: result["data"] ?? [])
                        models = try JSONDecoder().decode([StudyModel].self, from: data)
                    default: break
                    }
                }
            }
            return CodexConnection(login: login!, models: models!)
        }
    }

    static func explain(_ selection: StudySelection, model: StudyModel) async throws -> EnglishLesson {
        guard let cli = executable() else { throw CodexStudyError.missing }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ShadowingStudy-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let schema = folder.appendingPathComponent("schema.json"), result = folder.appendingPathComponent("lesson.json")
        try JSONSerialization.data(withJSONObject: EnglishLesson.schema).write(to: schema)
        let stderr = folder.appendingPathComponent("codex.log")
        FileManager.default.createFile(atPath: stderr.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: stderr)
        defer { try? errorHandle.close() }
        return try await CodexJob().run(timeout: 120) { job in
            let input = Pipe()
            let arguments = ["--no-daemon", "exec", "--ephemeral", "--ignore-user-config", "--ignore-rules",
                "--skip-git-repo-check", "--sandbox", "read-only", "--color", "never",
                "--disable", "shell_tool", "--disable", "plugins", "--disable", "apps",
                "--disable", "code_mode", "--disable", "code_mode_host",
                "-c", "web_search=\"disabled\"", "-c", "model_reasoning_effort=\"\(model.effort)\"",
                "--model", model.model, "--cd", folder.path,
                "--output-schema", schema.path, "--output-last-message", result.path, "-"]
            try job.start(cli, arguments: arguments, input: input, output: FileHandle.nullDevice, error: errorHandle)
            try input.fileHandleForWriting.write(contentsOf: Data(selection.prompt.utf8))
            try input.fileHandleForWriting.close()
            job.process.waitUntilExit()
            try job.check()
            guard job.process.terminationStatus == 0 else {
                let log = String(decoding: try Data(contentsOf: stderr), as: UTF8.self).lowercased()
                if log.contains("rate limit") || log.contains("usage limit") { throw CodexStudyError.failed("本机 Codex 账户额度已达上限，请稍后重试。") }
                if log.contains("login") || log.contains("401") { throw CodexStudyError.signedOut }
                throw CodexStudyError.failed("请确认 Codex 已更新、账户可用且网络正常，然后重试。")
            }
            guard let data = try? Data(contentsOf: result), let lesson = try? JSONDecoder().decode(EnglishLesson.self, from: data) else {
                throw CodexStudyError.failed("返回的讲解格式不完整，请重试。")
            }
            return lesson
        }
    }
}

// One owned child per operation. No credential files are read or copied by the player.
private final class CodexJob: @unchecked Sendable {
    let process = Process()
    private let lock = NSLock()
    private var cancelled = false
    private var timedOut = false

    func start(_ cli: URL, arguments: [String], input: Any, output: Any, error: Any) throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        process.executableURL = cli; process.arguments = arguments
        process.standardInput = input; process.standardOutput = output; process.standardError = error
        var environment = ProcessInfo.processInfo.environment
        for key in ["OPENAI_API_KEY", "CODEX_API_KEY", "CODEX_ACCESS_TOKEN", "OPENAI_BASE_URL"] { environment.removeValue(forKey: key) }
        process.environment = environment
        try process.run()
    }

    func check() throws {
        lock.lock(); defer { lock.unlock() }
        if timedOut { throw CodexStudyError.timeout }
        if cancelled { throw CancellationError() }
    }

    private func stop(cancel: Bool = false, timeout: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        cancelled = cancelled || cancel; timedOut = timedOut || timeout
        if process.isRunning { process.terminate() }
    }

    func run<T: Sendable>(timeout: Double, body: @escaping @Sendable (CodexJob) throws -> T) async throws -> T {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { [self] in
                    let deadline = DispatchWorkItem { self.stop(timeout: true) }
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                    let result = Result {
                        do { let value = try body(self); try check(); return value }
                        catch { try check(); throw error }
                    }
                    deadline.cancel(); stop()
                    if process.isRunning { process.waitUntilExit() }
                    continuation.resume(with: result)
                }
            }
        } onCancel: { self.stop(cancel: true) }
    }
}

@MainActor
final class EnglishStudyController: ObservableObject {
    @Published private(set) var status = "正在检测 Codex…"
    @Published private(set) var isChecking = false
    @Published private(set) var isLoggedIn = false
    @Published private(set) var models: [StudyModel] = []
    @Published var modelID = ""
    @Published var scope: StudyScope = .sentence
    @Published private(set) var selection: StudySelection?
    @Published private(set) var lesson: EnglishLesson?
    @Published private(set) var isLearning = false
    @Published private(set) var error: String?
    private var refreshTask: Task<Void, Never>?
    private var learningTask: Task<Void, Never>?
    private var generation = 0
    private var cache: [String: EnglishLesson] = [:]
    private var sourceSegments: [SubtitleSegment] = []
    var canLearn: Bool { isLoggedIn && !modelID.isEmpty }

    func refresh() {
        refreshTask?.cancel()
        isChecking = true
        refreshTask = Task {
            defer { if !Task.isCancelled { isChecking = false } }
            do {
                let connection = try await CodexBridge.connection()
                try Task.checkCancellation()
                models = connection.models
                isLoggedIn = connection.login == .chatGPT
                if !models.contains(where: { $0.id == modelID }) { modelID = StudyModel.preferred(in: models)?.id ?? "" }
                switch connection.login {
                case .chatGPT: status = "Codex 已登录"
                case .signedOut: status = "Codex 未登录"
                case .other: status = "Codex 需使用 ChatGPT 登录"
                }
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled else { return }
                isLoggedIn = false; status = error.localizedDescription
            }
        }
    }

    func learn(segments: [SubtitleSegment], focusID: Int) {
        cancel()
        guard let target = StudySelection(segments: segments, focusID: focusID, scope: scope) else { return }
        sourceSegments = segments
        selection = target; lesson = nil; error = nil
        guard isLoggedIn else { error = status; return }
        guard let model = models.first(where: { $0.id == modelID }) else { error = CodexStudyError.noModel.localizedDescription; return }
        let key = model.id + "\n" + target.prompt
        if let cached = cache[key] { lesson = cached; return }
        isLearning = true
        let token = generation
        learningTask = Task {
            do {
                let result = try await CodexBridge.explain(target, model: model)
                guard generation == token, !Task.isCancelled else { return }
                if cache.count >= 16 { cache.removeAll() }
                cache[key] = result; lesson = result; isLearning = false
            } catch {
                guard generation == token else { return }
                isLearning = false
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }

    func relearn() {
        guard let selection else { return }
        learn(segments: sourceSegments, focusID: selection.focusID)
    }

    func cancel() { generation += 1; learningTask?.cancel(); learningTask = nil; isLearning = false }
    isolated deinit { refreshTask?.cancel(); learningTask?.cancel() }
}
