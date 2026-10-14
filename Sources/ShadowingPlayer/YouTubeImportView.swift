import SwiftUI

struct YouTubeImportView: View {
    @ObservedObject var loader: YouTubeLoader
    let controller: PlayerController
    let dismiss: () -> Void
    @State private var link = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Practise with YouTube").font(.title2)
            Text("Paste a public YouTube video link. English captions and the video will be loaded into the native shadowing player.")
            TextField("https://www.youtube.com/watch?v=…", text: $link)
                .textFieldStyle(.roundedBorder).disabled(loader.isLoading)
                .accessibilityLabel("YouTube video URL")
            Text("Creator captions are preferred; YouTube automatic English captions are used when available. The video is temporarily cached until you replace it or quit.")
                .font(.callout).foregroundStyle(.secondary)
            if loader.isLoading {
                HStack { ProgressView().controlSize(.small); Text(loader.status) }
                Button("Cancel loading", action: loader.cancel)
            } else if !loader.status.isEmpty {
                Text(loader.status).font(.callout).foregroundStyle(.secondary)
            }
            if let error = loader.error {
                Text(error).foregroundStyle(.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Close") { loader.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Load & practise") { loader.load(link, into: controller, onLoaded: dismiss) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(loader.isLoading || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 560)
    }
}
