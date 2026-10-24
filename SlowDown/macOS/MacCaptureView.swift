import SwiftUI

struct MacCaptureView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var capture = SystemAudioCapture()
    @State private var title = ""
    let onFinish: (Recording) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Capture Audio From an App")
                .font(.title2.bold())
            Text("Pick the app that's playing — a browser for YouTube, Spotify, Music — press Record, then play the song. Only that app's sound is recorded, so notifications and other apps stay out.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Picker("Record from", selection: $capture.selectedAppID) {
                    Text("Everything the Mac plays").tag(String?.none)
                    Divider()
                    ForEach(capture.apps) { app in
                        Text(app.name).tag(Optional(app.id))
                    }
                }
                .disabled(capture.isRecording)
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await capture.refreshApps() }
                }
                .labelStyle(.iconOnly)
                .disabled(capture.isRecording)
            }

            TextField("Title (optional)", text: $title)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 16) {
                Text(capture.elapsed.preciseClock)
                    .font(.system(size: 32, weight: .semibold, design: .monospaced))
                LevelMeter(level: capture.level)
                    .frame(height: 8)
            }

            if let message = capture.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if message.contains("System Settings") {
                    Button("Open Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    Task {
                        if let url = await capture.stop() { try? FileManager.default.removeItem(at: url) }
                        dismiss()
                    }
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    Task { await toggle() }
                } label: {
                    Label(capture.isRecording ? "Stop & Add to Library" : "Record",
                          systemImage: capture.isRecording ? "stop.circle.fill" : "record.circle")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }

            Text("Capture is for personal practice. Respect the terms of the services you record from and the rights of the artists.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 520)
        .task { await capture.refreshApps() }
        .interactiveDismissDisabled(capture.isRecording)
    }

    private func toggle() async {
        if capture.isRecording {
            let source = capture.selectedAppName
            guard let url = await capture.stop() else { return }
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = trimmed.isEmpty ? StorageLocation.timestampedName(source.map { "\($0) Capture" } ?? "Mac Capture") : trimmed
            do {
                let recording = try library.addCapture(at: url, title: name, source: .systemCapture)
                onFinish(recording)
                dismiss()
            } catch {
                capture.errorMessage = error.localizedDescription
            }
        } else {
            await capture.start()
        }
    }
}
