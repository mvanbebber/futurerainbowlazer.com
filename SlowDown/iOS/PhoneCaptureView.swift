import ReplayKit
import SwiftUI

/// iOS can't record another app's audio directly; a ReplayKit broadcast ("screen recording") extension can.
/// The extension saves the app audio into the shared App Group, and the library picks it up on return.
struct PhoneCaptureView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Record the sound of YouTube, Spotify or any other app on this iPhone.")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 14) {
                        step(1, "Tap the record button below and choose **SlowDown Capture**, then **Start Broadcast**.")
                        step(2, "Switch to YouTube, Spotify or another app and play the song.")
                        step(3, "Come back and tap the button again — or tap the red status-bar pill — to stop.")
                        step(4, "The recording appears at the top of your library.")
                    }

                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            BroadcastPickerButton()
                                .frame(width: 80, height: 80)
                                .background(Circle().fill(.red.opacity(0.15)))
                            Text("Start / Stop Capture")
                                .font(.callout.bold())
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)

                    Label {
                        Text("Only app audio is saved — not the screen, and not the microphone. Turn on Do Not Disturb so notification sounds stay out of the recording.")
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    Label {
                        Text("Some apps mark their audio as protected (for example Apple Music, and some streaming apps), and iOS silences them in recordings. If a capture comes out silent, record with the microphone, or capture on your Mac.")
                    } icon: {
                        Image(systemName: "lock")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    Text("Capture is for personal practice. Respect the terms of the services you record from and the rights of the artists.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
            }
            .navigationTitle("Capture App Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        library.ingestPendingCaptures()
                        dismiss()
                    }
                }
            }
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.tint.opacity(0.2)))
            Text(text)
        }
    }
}

/// Apple's system broadcast picker, preset to SlowDown's extension so one tap starts capturing.
struct BroadcastPickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        picker.preferredExtension = (Bundle.main.bundleIdentifier ?? "com.futurerainbowlazer.slowdown") + ".Broadcast"
        picker.showsMicrophoneButton = false
        for case let button as UIButton in picker.subviews {
            button.imageView?.tintColor = .systemRed
            button.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 44), forImageIn: .normal)
        }
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
