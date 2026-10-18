import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import ShadowingCore
#endif
@testable import ShadowingPlayer

struct StudyNoteTests {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shadowing-notes-\(UUID())")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        return root
    }

    @Test func discoversRealConfiguredVaultsAndPrefersOpenVault() throws {
        let first = try directory(), second = try directory()
        defer { try? FileManager.default.removeItem(at: first); try? FileManager.default.removeItem(at: second) }
        let config = first.appendingPathComponent("config.json")
        let data: [String: Any] = ["cli": true, "vaults": [
            "closed": ["path": first.path, "ts": 200, "open": false],
            "open": ["path": second.path, "ts": 100, "open": true],
            "missing": ["path": first.appendingPathComponent("absent").path]
        ]]
        try JSONSerialization.data(withJSONObject: data).write(to: config)
        let vaults = try ObsidianVault.discover(configuration: config)
        #expect(vaults.map(\.id) == ["open", "closed"])
        #expect(try ObsidianVault.discover(configuration: first.appendingPathComponent("missing.json")).isEmpty)
        try Data("bad JSON".utf8).write(to: config)
        #expect(throws: DecodingError.self) { try ObsidianVault.discover(configuration: config) }
    }

    @Test func exportsCompleteMarkdownIntoVaultWithoutReplacingExistingNotes() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let selection = try #require(StudySelection(segments: [SubtitleSegment(id: 0, startTime: 1, endTime: 3, text: "Listen carefully.")], focusID: 0, scope: .sentence))
        let lesson = try JSONDecoder().decode(EnglishLesson.self, from: Data("""
        {"translation":"仔细听。","structure":"祈使句。","phrases":[],
         "listening":{"strategy":"抓关键词 listen。","chunks":[{"english":"Listen carefully.","meaning":"仔细听"}],
           "soundChanges":[{"excerpt":"carefully","explanation":"听重读音节。"}],"drill":"原速再听。"},
         "practice":[{"english":"Listen again.","chinese":"再听一次。"}],"question":"要做什么？","answer":"仔细听。"}
        """.utf8))
        let source = URL(string: "https://www.youtube.com/watch?v=abcdefghijk")!
        let markdown = StudyNote.markdown(selection: selection, lesson: lesson, sourceName: "A video",
                                          sourceURL: source, model: "test-model", playback: PlaybackInterval(start: 1, end: 3))
        let vault = ObsidianVault(id: "test", url: root, isOpen: true, lastUsed: 0)
        let first = try vault.save(markdown: markdown, sentence: selection.sentence)
        let second = try vault.save(markdown: "Second note", sentence: selection.sentence)
        #expect(first != second)
        #expect(first.deletingLastPathComponent().lastPathComponent == "Shadowing Player")
        #expect(try String(contentsOf: first, encoding: .utf8) == markdown)
        for text in ["Listen carefully.", "仔细听。", "test-model", source.absoluteString,
                     "1.000–3.000", "00:00:01.000 → 00:00:03.000", "视频原链接", "t=1s",
                     "## 按意群听", "carefully", "## 回听练习", "## 句法补充", "## 参考答案"] {
            #expect(markdown.contains(text))
        }
        // Reusing the lesson on another video must export the current source and timing.
        let later = try #require(StudySelection(segments: [SubtitleSegment(id: 99, startTime: 123.456, endTime: 126,
                                                                         text: selection.sentence)], focusID: 99, scope: .sentence))
        let other = URL(string: "https://youtu.be/otherSource")!
        let reused = StudyNote.markdown(selection: later, lesson: lesson, sourceName: "Another video",
                                        sourceURL: other, model: "original-cached-model", playback: nil)
        #expect(reused.contains(other.absoluteString) && reused.contains("t=123s"))
        #expect(reused.contains("00:02:03.456 → 00:02:06.000"))
        #expect(!reused.contains(source.absoluteString))
    }

    @Test func videoLinksPreserveVideoIdentityAndReplaceOldTimestamps() throws {
        let source = URL(string: "https://www.youtube.com/watch?v=abcdefghijk&t=2s&start=1#t=5")!
        let link = try #require(StudyNote.videoLink(source, start: 123.456))
        let items = try #require(URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first(where: { $0.name == "v" })?.value == "abcdefghijk")
        #expect(items.filter { $0.name == "t" }.map(\.value) == ["123s"])
        #expect(!items.contains { $0.name == "start" })
        #expect(link.fragment == nil)
        #expect(StudyNote.timestamp(3_723.456) == "01:02:03.456")
        #expect(StudyNote.timestamp(.infinity) == "—")
        #expect(StudyNote.videoLink(URL(fileURLWithPath: "/tmp/a video.mp4"), start: 3) == nil)
    }

    @Test func rejectsExportFolderSymlinkOutsideVaultAndRemovedVault() throws {
        let root = try directory(), outside = try directory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let vault = ObsidianVault(id: "test", url: root, isOpen: false, lastUsed: 0)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Shadowing Player"), withDestinationURL: outside)
        #expect(throws: CocoaError.self) { try vault.save(markdown: "note", sentence: "Example") }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path) == [".obsidian"])
        try FileManager.default.removeItem(at: root.appendingPathComponent(".obsidian"))
        #expect(throws: CocoaError.self) { try vault.save(markdown: "note", sentence: "Example") }
    }

    @Test func noteNamesAndOpenURIsHandleReservedCharacters() throws {
        let filename = StudyNote.filename(sentence: "../../Hello: /? #中文\nWorld", date: Date(timeIntervalSince1970: 0),
                                          id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
        #expect(filename.hasSuffix("- 00000000.md"))
        #expect(!filename.contains("/") && !filename.contains(":") && !filename.contains("\n"))
        let file = URL(fileURLWithPath: "/tmp/My vault/听力 & #1?.md")
        let uri = try #require(ObsidianVault.openURL(for: file))
        #expect(uri.scheme == "obsidian" && uri.host == "open")
        #expect(uri.absoluteString.contains("%2Ftmp%2FMy%20vault%2F"))
        #expect(URLComponents(url: uri, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == file.path)
    }
}
