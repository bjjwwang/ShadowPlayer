import AppKit
import Combine
#if SWIFT_PACKAGE
import ShadowingCore
#endif

struct ObsidianVault: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let isOpen: Bool
    let lastUsed: Double
    var name: String { url.lastPathComponent }

    static func discover(configuration: URL) throws -> [Self] {
        guard FileManager.default.fileExists(atPath: configuration.path) else { return [] }
        struct Config: Decodable {
            struct Entry: Decodable { let path: String; let open: Bool?; let ts: Double? }
            let vaults: [String: Entry]
        }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: configuration))
        return config.vaults.compactMap { id, entry in
            let url = URL(fileURLWithPath: entry.path, isDirectory: true).resolvingSymlinksInPath()
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.appendingPathComponent(".obsidian").path, isDirectory: &directory),
                  directory.boolValue else { return nil }
            return Self(id: id, url: url, isOpen: entry.open ?? false, lastUsed: entry.ts ?? 0)
        }.sorted {
            if $0.isOpen != $1.isOpen { return $0.isOpen }
            if $0.lastUsed != $1.lastUsed { return $0.lastUsed > $1.lastUsed }
            return $0.id < $1.id
        }
    }

    func save(markdown: String, sentence: String) throws -> URL {
        let manager = FileManager.default
        let root = url.resolvingSymlinksInPath()
        guard manager.fileExists(atPath: root.appendingPathComponent(".obsidian").path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let folder = root.appendingPathComponent("Shadowing Player", isDirectory: true)
        // Do not follow an existing export-folder symlink outside this vault.
        guard folder.resolvingSymlinksInPath().path.hasPrefix(root.path + "/") else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(StudyNote.filename(sentence: sentence))
        try Data(markdown.utf8).write(to: file, options: .withoutOverwriting)
        return file
    }

    static func openURL(for file: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "obsidian"; components.host = "open"
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let path = file.path.addingPercentEncoding(withAllowedCharacters: unreserved) else { return nil }
        components.percentEncodedQuery = "path=" + path
        return components.url
    }
}

@MainActor
final class ObsidianExporter: ObservableObject {
    @Published private(set) var vaults: [ObsidianVault] = []
    @Published var vaultID = ""
    @Published private(set) var savedURL: URL?
    @Published private(set) var error: String?
    var selectedVault: ObsidianVault? { vaults.first { $0.id == vaultID } }

    func refresh() {
        do {
            let file = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/obsidian/obsidian.json")
            vaults = try ObsidianVault.discover(configuration: file)
            if !vaults.contains(where: { $0.id == vaultID }) { vaultID = vaults.first?.id ?? "" }
            error = nil
        } catch { self.error = "无法读取 Obsidian 配置：\(error.localizedDescription)" }
    }

    func save(markdown: String, sentence: String) {
        guard let vault = selectedVault, savedURL == nil else { return }
        do { savedURL = try vault.save(markdown: markdown, sentence: sentence); error = nil }
        catch { self.error = "保存失败：\(error.localizedDescription)" }
    }

    func openSaved() {
        guard let savedURL, let uri = ObsidianVault.openURL(for: savedURL) else { return }
        if !NSWorkspace.shared.open(uri) { error = "笔记已保存，但未能打开 Obsidian。请在 vault 的 Shadowing Player 文件夹中查看。" }
    }

    func resetSaved() { savedURL = nil; error = nil }
}
