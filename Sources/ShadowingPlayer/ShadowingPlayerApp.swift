import SwiftUI

@main
struct ShadowingPlayerApp: App {
    @StateObject private var controller = PlayerController()

    var body: some Scene {
        WindowGroup("Shadowing Player") {
            MainContentView(controller: controller)
                .frame(minWidth: 900, minHeight: 680)
        }
        .defaultSize(width: 1_000, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Video…", action: controller.openVideo).keyboardShortcut("o")
                Button("Import SRT…", action: controller.importSubtitles).keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}
