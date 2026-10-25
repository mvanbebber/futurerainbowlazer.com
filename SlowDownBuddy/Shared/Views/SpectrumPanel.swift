import SwiftUI

/// Piano-keyboard spectrum: which notes are sounding at the playhead (after transposition).
struct SpectrumPanel: View {
    let controller: PlayerController
    @State private var levels: [Float] = []

    private let low = SpectrumAnalyzer.lowestNote
    private let high = SpectrumAnalyzer.highestNote

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Strongest notes").foregroundStyle(.secondary)
                ForEach(strongestNotes, id: \.self) { note in
                    Text(SpectrumAnalyzer.noteName(note))
                        .font(.headline.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.tint.opacity(0.2), in: Capsule())
                }
                Spacer()
            }
            Canvas { context, size in
                draw(in: context, size: size)
            }
            .frame(height: 140)
            .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 10))
            Text("Pause on a chord or note to see what's sounding. Tip: loop a short bit at a slow speed and use the EQ to isolate the instrument.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task(id: controller.recording.id) {
            guard let analyzer = try? SpectrumAnalyzer(url: controller.audioURL) else { return }
            var lastTime = -1.0
            var lastPitch = Double.nan
            while !Task.isCancelled {
                let time = controller.engine.currentTime
                let pitch = controller.recording.settings.pitchCents
                if abs(time - lastTime) > 0.02 || pitch != lastPitch {
                    levels = await analyzer.noteLevels(at: time, transpositionCents: pitch)
                    lastTime = time
                    lastPitch = pitch
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    private var strongestNotes: [Int] {
        levels.enumerated()
            .filter { $0.element > 0.45 }
            .sorted { $0.element > $1.element }
            .prefix(4)
            .map { $0.offset + low }
            .sorted()
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        let count = high - low + 1
        let keyWidth = size.width / CGFloat(count)
        let keyboardHeight: CGFloat = 22
        let barArea = size.height - keyboardHeight - 4
        let blackKeys: Set<Int> = [1, 3, 6, 8, 10]

        for index in 0..<count {
            let note = low + index
            let x = CGFloat(index) * keyWidth
            let level = index < levels.count ? CGFloat(levels[index]) : 0
            let barHeight = level * barArea
            let hue = Double(note % 12) / 12
            context.fill(
                Path(CGRect(x: x + 0.5, y: barArea - barHeight + 2, width: max(keyWidth - 1, 1), height: barHeight)),
                with: .color(Color(hue: hue, saturation: 0.7, brightness: 0.95)))
            let isBlack = blackKeys.contains(note % 12)
            context.fill(
                Path(CGRect(x: x, y: size.height - keyboardHeight, width: max(keyWidth - 0.5, 0.5), height: keyboardHeight)),
                with: .color(isBlack ? Color(white: 0.15) : Color(white: 0.92)))
            if note % 12 == 0 {
                context.draw(
                    Text("C\(note / 12 - 1)").font(.system(size: 8)).foregroundStyle(.black),
                    at: CGPoint(x: x + 1, y: size.height - 10), anchor: .leading)
            }
        }
    }
}
