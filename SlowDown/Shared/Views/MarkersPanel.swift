import SwiftUI

/// Section, measure and beat markers: add at the playhead, rename, jump to, loop a section.
struct MarkersPanel: View {
    let controller: PlayerController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ForEach(Marker.Kind.allCases) { kind in
                    Button("\(kind.title)", systemImage: kind.symbolName) { controller.addMarker(kind) }
                        .buttonStyle(.bordered)
                }
            }
            Text("Adds a marker at the playhead. Keys: S section, M measure, N beat — tap them along while the song plays.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if controller.recording.markers.isEmpty {
                Text("No markers yet.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(controller.recording.markers) { marker in
                        MarkerRow(controller: controller, marker: marker)
                        Divider()
                    }
                }
            }
        }
    }
}

private struct MarkerRow: View {
    let controller: PlayerController
    let marker: Marker
    @State private var label = ""

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: marker.kind.symbolName)
                .foregroundStyle(marker.kind == .section ? .orange : .secondary)
                .frame(width: 20)
            Button(marker.time.preciseClock) { controller.seek(to: marker.time) }
                .font(.system(.body, design: .monospaced))
                .buttonStyle(.borderless)
            TextField(controller.label(for: marker), text: $label)
                .textFieldStyle(.plain)
                .onSubmit { controller.renameMarker(marker.id, to: label) }
                .onAppear { label = marker.label }
            Spacer(minLength: 0)
            Menu {
                Button("Loop From Here", systemImage: "repeat") { controller.loopFrom(marker) }
                Button("Move to Playhead", systemImage: "arrow.right.to.line") { controller.moveMarkerToPlayhead(marker.id) }
                Button("Delete", systemImage: "trash", role: .destructive) { controller.deleteMarker(marker.id) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
        }
        .padding(.vertical, 6)
        .onChange(of: label) { _, newValue in
            if newValue != marker.label { controller.renameMarker(marker.id, to: newValue) }
        }
    }
}
