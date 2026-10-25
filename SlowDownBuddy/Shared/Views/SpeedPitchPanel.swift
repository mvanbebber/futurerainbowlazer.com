import SwiftUI

/// Speed (without changing pitch), transposition and fine tuning (without changing speed), volume and channels.
struct SpeedPitchPanel: View {
    @Bindable var controller: PlayerController

    private let speedPresets: [Double] = [0.5, 0.6, 0.7, 0.75, 0.8, 0.9, 1.0]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Speed
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Speed", systemImage: "tortoise")
                        .font(.headline)
                    Spacer()
                    Text("\(Int((controller.speed * 100).rounded()))%")
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                }
                HStack {
                    Button("Slower", systemImage: "minus") { controller.speed -= 0.05 }
                        .playerShortcut("[", enabled: !controller.isEditingText)
                    Slider(value: $controller.speed, in: PlayerController.speedRange, step: 0.01)
                    Button("Faster", systemImage: "plus") { controller.speed += 0.05 }
                        .playerShortcut("]", enabled: !controller.isEditingText)
                }
                .labelStyle(.iconOnly)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(speedPresets, id: \.self) { preset in
                            Button("\(Int(preset * 100))%") { controller.speed = preset }
                                .buttonStyle(.bordered)
                                .tint(abs(controller.speed - preset) < 0.001 ? Color.accentColor : Color.gray)
                        }
                    }
                }
            }

            Divider()

            // Pitch
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Pitch", systemImage: "tuningfork")
                        .font(.headline)
                    Spacer()
                    Text(pitchDescription)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                }
                HStack(spacing: 16) {
                    Stepper(value: $controller.semitones, in: PlayerController.semitoneRange) {
                        Text("\(controller.semitones, format: .number.sign(strategy: .always(includingZero: false))) st")
                            .monospacedDigit()
                    }
                    .fixedSize()
                    Button("−12") { controller.semitones -= 12 }
                        .buttonStyle(.bordered)
                        .help("Down an octave")
                    Button("+12") { controller.semitones += 12 }
                        .buttonStyle(.bordered)
                        .help("Up an octave")
                    Spacer(minLength: 0)
                }
                HStack {
                    Text("Fine tune")
                        .foregroundStyle(.secondary)
                    Slider(value: $controller.cents, in: -50...50, step: 1)
                    Text("\(Int(controller.cents), format: .number.sign(strategy: .always(includingZero: false))) ¢")
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                    Button("Reset Pitch", systemImage: "arrow.counterclockwise") { controller.resetPitch() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(controller.semitones == 0 && controller.cents == 0)
                }
            }

            Divider()

            HStack(spacing: 12) {
                Image(systemName: "speaker.wave.2")
                    .foregroundStyle(.secondary)
                Slider(value: $controller.volume, in: 0...1)
            }
            HStack {
                Label("Channels", systemImage: "hifispeaker.2")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if controller.engine.isProcessingChannels {
                    ProgressView().controlSize(.small)
                }
                Picker("Channels", selection: $controller.channelMode) {
                    ForEach(ChannelMode.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .disabled(controller.engine.channelCount < 2)
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var pitchDescription: String {
        let total = controller.recording.settings.pitchCents
        guard total != 0 else { return "Original" }
        let semis = controller.semitones
        let cents = Int(controller.cents)
        var parts: [String] = []
        if semis != 0 { parts.append(String(format: "%+ld st", semis)) }
        if cents != 0 { parts.append(String(format: "%+ld ¢", cents)) }
        return parts.joined(separator: " ")
    }
}
