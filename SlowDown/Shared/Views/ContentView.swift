import SwiftUI

struct ContentView: View {
    @Environment(Library.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Recording.ID?

    var body: some View {
        NavigationSplitView {
            LibraryView(selection: $selection)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
                #endif
        } detail: {
            if let id = selection, let recording = library.recording(with: id) {
                PlayerView(recording: recording)
                    .id(id)
            } else {
                ContentUnavailableView(
                    "No Recording Selected",
                    systemImage: "waveform",
                    description: Text("Import a song, drop a file here, or capture audio playing in YouTube, Spotify or any other app."))
            }
        }
        .onOpenURL { url in
            Task {
                if let recording = await library.importFiles([url]) { selection = recording.id }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { library.ingestPendingCaptures() }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } }),
            presenting: library.errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }
}
