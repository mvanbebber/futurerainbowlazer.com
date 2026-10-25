import SwiftUI

/// Records from the microphone, e.g. a song playing on a speaker, car stereo or another device.
struct MicRecordView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = MicRecorder()
    @State private var errorMessage: String?
    let onFinish: (Recording) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Record With Microphone")
                .font(.title2.bold())
            Text("Hold your device near the speaker. For the cleanest sound, capture the app's audio directly instead.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text(recorder.elapsed.preciseClock)
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
            LevelMeter(level: recorder.level)
                .frame(height: 8)
            Button {
                Task { await toggle() }
            } label: {
                Label(recorder.isRecording ? "Stop" : "Record",
                      systemImage: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                    .font(.title2)
                    .frame(maxWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }
            Button("Cancel", role: .cancel) {
                if let url = recorder.stop() { try? FileManager.default.removeItem(at: url) }
                dismiss()
            }
        }
        .padding(28)
        .frame(minWidth: 360)
        .interactiveDismissDisabled(recorder.isRecording)
    }

    private func toggle() async {
        if recorder.isRecording {
            guard let url = recorder.stop() else { return }
            do {
                let recording = try library.addCapture(
                    at: url, title: StorageLocation.timestampedName("Mic Recording"), source: .microphone)
                onFinish(recording)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            do {
                try await recorder.start()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct LevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(LinearGradient(colors: [.green, .yellow, .red], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * CGFloat(min(max(level, 0), 1)))
                    .animation(.linear(duration: 0.08), value: level)
            }
        }
    }
}
