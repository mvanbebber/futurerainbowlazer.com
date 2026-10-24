import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(Library.self) private var library
    @Binding var selection: Recording.ID?

    @State private var showingImporter = false
    @State private var showingCapture = false
    @State private var showingMicRecorder = false
    @State private var renaming: Recording?
    @State private var newTitle = ""

    static let importTypes: [UTType] = [.audio, .movie, .mpeg4Movie, .quickTimeMovie, .audiovisualContent]

    var body: some View {
        List(selection: $selection) {
            ForEach(library.recordings) { recording in
                NavigationLink(value: recording.id) {
                    RecordingRow(recording: recording)
                }
                .contextMenu {
                    Button("Rename…", systemImage: "pencil") {
                        newTitle = recording.title
                        renaming = recording
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        delete(recording.id)
                    }
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        delete(recording.id)
                    }
                }
            }
        }
        .overlay {
            if library.recordings.isEmpty {
                ContentUnavailableView {
                    Label("No Recordings", systemImage: "music.note.list")
                } description: {
                    Text("Import WAV, FLAC, MP3, M4A, MP4, Voice Memos and more — or capture what's playing in YouTube or Spotify.")
                } actions: {
                    Button("Import Audio or Video…") { showingImporter = true }
                    Button("Capture Audio From an App…") { showingCapture = true }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if library.importingCount > 0 {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Importing…").font(.callout).foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
        }
        .navigationTitle("SlowDown")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Import Audio or Video…", systemImage: "square.and.arrow.down") { showingImporter = true }
                    Button("Capture Audio From an App…", systemImage: "record.circle") { showingCapture = true }
                    Button("Record With Microphone…", systemImage: "mic") { showingMicRecorder = true }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: Self.importTypes, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task {
                    if let recording = await library.importFiles(urls) { selection = recording.id }
                }
            case .failure(let error):
                library.errorMessage = error.localizedDescription
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            Task {
                if let recording = await library.importFiles(files) { selection = recording.id }
            }
            return true
        }
        .sheet(isPresented: $showingCapture) {
            CaptureView { recording in selection = recording.id }
        }
        .sheet(isPresented: $showingMicRecorder) {
            MicRecordView { recording in selection = recording.id }
        }
        .alert("Rename Recording", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Rename") {
                if let renaming { library.rename(renaming.id, to: newTitle) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private func delete(_ id: Recording.ID) {
        if selection == id { selection = nil }
        library.delete(id)
    }
}

private struct RecordingRow: View {
    let recording: Recording

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: recording.source.symbolName)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.title)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(recording.duration.shortClock)
                    if recording.settings.speed != 1 {
                        Text("\(Int((recording.settings.speed * 100).rounded()))%")
                    }
                    if recording.settings.pitchCents != 0 {
                        Text(String(format: "%+.0f st", recording.settings.pitchCents / 100))
                    }
                    if !recording.markers.isEmpty {
                        Label("\(recording.markers.count)", systemImage: "flag")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
        }
        .padding(.vertical, 2)
    }
}
