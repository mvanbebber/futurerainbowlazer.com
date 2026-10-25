import SwiftUI

/// Five-band EQ with presets for picking out an instrument (e.g. "Bass focus" to hear a bass line).
struct EQPanel: View {
    let controller: PlayerController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(EQBand.presets, id: \.name) { preset in
                        Button(preset.name) { controller.applyEQPreset(preset.gains) }
                            .buttonStyle(.bordered)
                            .tint(isActive(preset.gains) ? Color.accentColor : Color.gray)
                    }
                }
            }
            ForEach(Array(EQBand.all.enumerated()), id: \.offset) { index, band in
                HStack {
                    VStack(alignment: .leading) {
                        Text(band.label)
                        Text(frequencyLabel(band.frequency)).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(width: 80, alignment: .leading)
                    Slider(
                        value: Binding(get: { controller.eqGain(index) }, set: { controller.setEQGain(index, $0) }),
                        in: -24...24, step: 1)
                    Text("\(Int(controller.eqGain(index)), format: .number.sign(strategy: .always(includingZero: false))) dB")
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
                }
            }
        }
    }

    private func isActive(_ gains: [Double]) -> Bool {
        gains.enumerated().allSatisfy { controller.eqGain($0.offset) == $0.element }
    }

    private func frequencyLabel(_ hz: Float) -> String {
        hz >= 1000 ? "\(Int(hz / 1000)) kHz" : "\(Int(hz)) Hz"
    }
}
