import SwiftUI

/// Play/pause, skipping, marker navigation and A–B loop controls, with Transcribe!-style keyboard shortcuts.
struct TransportBar: View {
    let controller: PlayerController

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 18) {
                Button("Previous Marker", systemImage: "backward.end.fill") { controller.previousMarker() }
                    .keyboardShortcut(.leftArrow, modifiers: .option)
                Button("Back 5 Seconds", systemImage: "gobackward.5") { controller.skip(by: -5) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button(controller.engine.isPlaying ? "Pause" : "Play",
                       systemImage: controller.engine.isPlaying ? "pause.circle.fill" : "play.circle.fill") {
                    controller.togglePlay()
                }
                .font(.system(size: 52))
                .keyboardShortcut(.space, modifiers: [])
                Button("Forward 5 Seconds", systemImage: "goforward.5") { controller.skip(by: 5) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("Next Marker", systemImage: "forward.end.fill") { controller.nextMarker() }
                    .keyboardShortcut(.rightArrow, modifiers: .option)
            }
            .font(.title2)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                Button("Set A", systemImage: "a.square") { controller.setLoopStartAtPlayhead() }
                    .keyboardShortcut("a", modifiers: [])
                Button("Set B", systemImage: "b.square") { controller.setLoopEndAtPlayhead() }
                    .keyboardShortcut("b", modifiers: [])
                Toggle(isOn: Binding(get: { controller.loopEnabled }, set: { controller.loopEnabled = $0 })) {
                    Label("Loop", systemImage: "repeat")
                }
                .toggleStyle(.button)
                .keyboardShortcut("l", modifiers: [])
                Button("To Start", systemImage: "arrow.uturn.backward") { controller.goToStart() }
                    .keyboardShortcut(.return, modifiers: [])
                Spacer(minLength: 0)
                Menu {
                    ForEach(Marker.Kind.allCases) { kind in
                        Button("Add \(kind.title) Marker", systemImage: kind.symbolName) { controller.addMarker(kind) }
                    }
                } label: {
                    Label("Marker", systemImage: "flag")
                } primaryAction: {
                    controller.addMarker(.measure)
                }
                .fixedSize()
                // Hidden buttons give each marker type its own key: M = measure, S = section, N = beat.
                .background {
                    Group {
                        Button("") { controller.addMarker(.measure) }.keyboardShortcut("m", modifiers: [])
                        Button("") { controller.addMarker(.section) }.keyboardShortcut("s", modifiers: [])
                        Button("") { controller.addMarker(.beat) }.keyboardShortcut("n", modifiers: [])
                    }
                    .opacity(0)
                    .accessibilityHidden(true)
                }
            }
            .buttonStyle(.bordered)

            if let a = controller.loopStart, let b = controller.loopEnd {
                HStack(spacing: 6) {
                    Image(systemName: "repeat").foregroundStyle(controller.loopActive ? .yellow : .secondary)
                    Text("\(a.preciseClock) – \(b.preciseClock)")
                    Text("(\(String(format: "%.2f", b - a)) s)").foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear", role: .destructive) { controller.clearLoop() }
                        .buttonStyle(.borderless)
                }
                .font(.system(.callout, design: .monospaced))
            }
        }
    }
}
