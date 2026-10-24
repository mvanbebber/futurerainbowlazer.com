import SwiftUI

/// Fine-adjust the current A–B loop and keep a list of named loops ("Solo", "Bridge riff", …).
struct LoopsPanel: View {
    let controller: PlayerController
    @State private var newName = ""
    @FocusState private var editingName: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let a = controller.loopStart, let b = controller.loopEnd {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    nudgeRow("Start", time: a, isStart: true)
                    nudgeRow("End", time: b, isStart: false)
                }
                HStack {
                    TextField("Loop name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .focused($editingName)
                        .onSubmit(save)
                    Button("Save Loop", systemImage: "plus", action: save)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Text("Drag across the waveform, or press A and B while playing, to make a loop.")
                    .foregroundStyle(.secondary)
            }

            if !controller.recording.loops.isEmpty {
                Text("Saved Loops").font(.headline).padding(.top, 4)
                LazyVStack(spacing: 0) {
                    ForEach(controller.recording.loops) { loop in
                        HStack {
                            Button {
                                controller.activate(loop)
                                if !controller.engine.isPlaying { controller.togglePlay() }
                            } label: {
                                Label(loop.name, systemImage: "repeat")
                            }
                            .buttonStyle(.borderless)
                            Spacer()
                            Text("\(loop.start.preciseClock) – \(loop.end.preciseClock)")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                controller.deleteLoop(loop.id)
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
            }
        }
        .onChange(of: editingName) { _, isEditing in controller.isEditingText = isEditing }
    }

    private func save() {
        editingName = false
        controller.saveCurrentLoop(named: newName)
        newName = ""
    }

    private func nudgeRow(_ title: String, time: TimeInterval, isStart: Bool) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(time.preciseClock).font(.system(.body, design: .monospaced))
            HStack(spacing: 4) {
                ForEach([-0.5, -0.05, 0.05, 0.5], id: \.self) { delta in
                    Button(String(format: "%+.2f", delta)) { controller.nudgeLoop(start: isStart, by: delta) }
                        .buttonStyle(.bordered)
                        .font(.caption.monospacedDigit())
                }
            }
        }
    }
}
