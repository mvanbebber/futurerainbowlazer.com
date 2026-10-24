import AVFoundation
import Accelerate

/// Estimates how strongly each piano note sounds around a point in the song — the "which notes are these?"
/// spectrum view from Transcribe!.
///
/// A long (≈0.7 s) Hann-windowed FFT is taken around the playhead and the energy within ±50 cents of each
/// equal-tempered note (A4 = 440 Hz) is reported, shifted by the current transposition so the notes match
/// what you hear.
actor SpectrumAnalyzer {
    static let lowestNote = 28 // E1, the low string of a bass guitar
    static let highestNote = 96 // C7

    private let file: AVAudioFile
    private let size = 32_768
    private let fft: vDSP.FFT<DSPSplitComplex>
    private let window: [Float]
    private let buffer: AVAudioPCMBuffer

    init(url: URL) throws {
        file = try AVAudioFile(forReading: url)
        guard let fft = vDSP.FFT(log2n: 15, radix: .radix2, ofType: DSPSplitComplex.self),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(32_768))
        else { throw AudioImporter.ImportError.unreadable }
        self.fft = fft
        self.buffer = buffer
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: 32_768, isHalfWindow: false)
    }

    /// Relative level (0…1) of each note from `lowestNote` through `highestNote`.
    func noteLevels(at time: TimeInterval, transpositionCents: Double) -> [Float] {
        let sampleRate = file.processingFormat.sampleRate
        let center = AVAudioFramePosition(time * sampleRate)
        let start = max(0, min(center - AVAudioFramePosition(size / 2), file.length - AVAudioFramePosition(size)))
        file.framePosition = start
        do {
            try file.read(into: buffer, frameCount: AVAudioFrameCount(size))
        } catch {
            return []
        }
        let frames = Int(buffer.frameLength)
        guard frames > 0, let data = buffer.floatChannelData else { return [] }

        var signal = [Float](repeating: 0, count: size)
        for ch in 0..<Int(buffer.format.channelCount) {
            let channel = data[ch]
            for i in 0..<frames { signal[i] += channel[i] }
        }
        signal = vDSP.multiply(signal, window)

        let half = size / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                signal.withUnsafeBytes { raw in
                    let complex = raw.bindMemory(to: DSPComplex.self)
                    vDSP_ctoz(complex.baseAddress!, 2, &split, 1, vDSP_Length(half))
                }
                let input = split
                fft.forward(input: input, output: &split)
                magnitudes.withUnsafeMutableBufferPointer { magPtr in
                    vDSP_zvmags(&split, 1, magPtr.baseAddress!, 1, vDSP_Length(half))
                }
            }
        }

        // Frequencies in the file are shifted by the transposition on playback.
        let shift = pow(2.0, transpositionCents / 1200)
        let binWidth = sampleRate / Double(size)
        var levels: [Float] = []
        for note in Self.lowestNote...Self.highestNote {
            let heard = 440 * pow(2.0, Double(note - 69) / 12)
            let sourceFrequency = heard / shift
            let lowBin = Int((sourceFrequency * pow(2.0, -1.0 / 24)) / binWidth)
            let highBin = Int((sourceFrequency * pow(2.0, 1.0 / 24)) / binWidth)
            let lower = max(1, lowBin)
            let upper = min(half - 1, max(lower, highBin))
            var peak: Float = 0
            if lower <= upper {
                for bin in lower...upper where magnitudes[bin] > peak { peak = magnitudes[bin] }
            }
            levels.append(sqrt(peak))
        }
        let loudest = levels.max() ?? 0
        guard loudest > 0 else { return levels }
        return levels.map { pow($0 / loudest, 1.5) }
    }

    static func noteName(_ midi: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return "\(names[((midi % 12) + 12) % 12])\(midi / 12 - 1)"
    }
}
