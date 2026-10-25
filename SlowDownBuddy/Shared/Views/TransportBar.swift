import SwiftUI

/// Play/pause, skipping, marker navigation and A–B loop controls, with Transcribe!-style keyboard shortcuts.
struct TransportBar: View {
    let controller: PlayerController

    private var keys: Bool { !controller.isEditingText }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 18) {
                Button("Previous Marker", systemImage: "backward.end.fill") { controller.previousMarker() }
                    .playerShortcut(.leftArrow, modifiers: .option, enabled: keys)
                Button("Back 5 Seconds", systemImage: "gobackward.5") { controller.skip(by: -5) }
                    .playerShortcut(.leftArrow, modifiers: [], enabled: keys)
                Button(controller.engine.isPlaying ? "Pause" : "Play",
                       systemImage: controller.engine.isPlaying ? "pause.circle.fill" : "play.circle.fill") {
                    controller.togglePlay()
                }
                .font(.system(size: 52))
                .playerShortcut(.space, modifiers: [], enabled: keys)
                Button("Forward 5 Seconds", systemImage: "goforward.5") { controller.skip(by: 5) }
                    .playerShortcut(.rightArrow, modifiers: [], enabled: keys)
                Button("Next Marker", systemImage: "forward.end.fill") { controller.nextMarker() }
                    .playerShortcut(.rightArrow, modifiers: .option, enabled: keys)
            }
            .font(.title2)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity)

            // Titles where there's room (Mac, iPad), icons only on a phone.
            ViewThatFits(in: .horizontal) {
                loopRow.labelStyle(.titleAndIcon)
                loopRow.labelStyle(.iconOnly)
            }

            if let a = controller.loopStart, let b = controller.loopEnd {
                HStack(spacing: 6) {
                    Image(systemName: "repeat").foregroundStyle(controller.loopActive ? Color.yellow : Color.secondary)
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

    private var loopRow: some View {
        HStack(spacing: 10) {
            Button("Set A", systemImage: "a.square") { controller.setLoopStartAtPlayhead() }
                .playerShortcut("a", modifiers: [], enabled: keys)
            Button("Set B", systemImage: "b.square") { controller.setLoopEndAtPlayhead() }
                .playerShortcut("b", modifiers: [], enabled: keys)
            Toggle(isOn: Binding(get: { controller.loopEnabled }, set: { controller.loopEnabled = $0 })) {
                Label("Loop", systemImage: "repeat")
            }
            .toggleStyle(.button)
            .playerShortcut("l", modifiers: [], enabled: keys)
            Button("To Start", systemImage: "arrow.uturn.backward") { controller.goToStart() }
                .playerShortcut(.return, modifiers: [], enabled: keys)
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
                    Button("") { controller.addMarker(.measure) }.playerShortcut("m", modifiers: [], enabled: keys)
                    Button("") { controller.addMarker(.section) }.playerShortcut("s", modifiers: [], enabled: keys)
                    Button("") { controller.addMarker(.beat) }.playerShortcut("n", modifiers: [], enabled: keys)
                }
                .opacity(0)
                .accessibilityHidden(true)
            }
        }
        .buttonStyle(.bordered)
    }
}
