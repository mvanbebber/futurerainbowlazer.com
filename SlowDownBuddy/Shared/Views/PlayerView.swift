import SwiftUI

struct PlayerView: View {
    @Environment(Library.self) private var library
    let recording: Recording
    @State private var controller: PlayerController?

    var body: some View {
        Group {
            if let controller {
                PlayerContent(controller: controller)
            } else {
                ProgressView()
            }
        }
        .task {
            let controller = PlayerController(recording: recording, library: library)
            self.controller = controller
            await controller.load()
        }
        .onDisappear {
            controller?.close()
        }
    }
}

private enum PlayerPanel: String, CaseIterable, Identifiable {
    case markers = "Markers"
    case loops = "Loops"
    case eq = "EQ"
    case notes = "Notes"

    var id: String { rawValue }
}

private struct PlayerContent: View {
    @Bindable var controller: PlayerController
    @State private var panel: PlayerPanel = .markers

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let message = controller.errorMessage ?? controller.engine.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
                WaveformView(controller: controller)
                TransportBar(controller: controller)
                SpeedPitchPanel(controller: controller)
                Picker("Panel", selection: $panel) {
                    ForEach(PlayerPanel.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                switch panel {
                case .markers: MarkersPanel(controller: controller)
                case .loops: LoopsPanel(controller: controller)
                case .eq: EQPanel(controller: controller)
                case .notes: SpectrumPanel(controller: controller)
                }
            }
            .padding()
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(controller.recording.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(controller.engine.currentTime.preciseClock)
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .contentTransition(.numericText())
            Text("/ \(controller.engine.duration.preciseClock)")
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            if let marker = currentMarker {
                let label = controller.label(for: marker)
                Label(marker.kind == .measure ? "Bar \(label)" : label, systemImage: marker.kind.symbolName)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The most recent section (or measure) marker before the playhead.
    private var currentMarker: Marker? {
        let now = controller.engine.currentTime
        let passed = controller.recording.markers.filter { $0.time <= now + 0.01 }
        return passed.last(where: { $0.kind == .section }) ?? passed.last(where: { $0.kind == .measure })
    }
}
