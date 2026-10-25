import AVFoundation
import Accelerate

/// Peak amplitudes of a file at a fixed resolution, used to draw the waveform at any zoom level.
struct WaveformData {
    let peaks: [Float]
    let peaksPerSecond: Double

    static let targetPeaksPerSecond = 200.0

    /// Loudest peak between two times.
    func peak(from start: TimeInterval, to end: TimeInterval) -> Float {
        let lower = max(0, Int(start * peaksPerSecond))
        let upper = min(peaks.count, max(lower + 1, Int(end * peaksPerSecond)))
        guard lower < upper else { return 0 }
        var result: Float = 0
        for i in lower..<upper where peaks[i] > result { result = peaks[i] }
        return result
    }

    static func load(url: URL) async throws -> WaveformData {
        try await Task.detached(priority: .utility) {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let framesPerPeak = max(1, Int(format.sampleRate / WaveformData.targetPeaksPerSecond))
            let capacity = AVAudioFrameCount(framesPerPeak * 512)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                throw AudioImporter.ImportError.unreadable
            }
            var peaks: [Float] = []
            peaks.reserveCapacity(Int(file.length) / framesPerPeak + 1)
            var binPeak: Float = 0
            var binFill = 0
            let channels = Int(format.channelCount)

            while file.framePosition < file.length {
                try file.read(into: buffer)
                let frames = Int(buffer.frameLength)
                guard frames > 0, let data = buffer.floatChannelData else { break }
                var index = 0
                while index < frames {
                    let take = min(framesPerPeak - binFill, frames - index)
                    for ch in 0..<channels {
                        var channelPeak: Float = 0
                        vDSP_maxmgv(data[ch] + index, 1, &channelPeak, vDSP_Length(take))
                        binPeak = max(binPeak, channelPeak)
                    }
                    binFill += take
                    index += take
                    if binFill == framesPerPeak {
                        peaks.append(min(binPeak, 1))
                        binPeak = 0
                        binFill = 0
                    }
                }
                if Task.isCancelled { throw CancellationError() }
            }
            if binFill > 0 { peaks.append(min(binPeak, 1)) }
            return WaveformData(peaks: peaks, peaksPerSecond: format.sampleRate / Double(framesPerPeak))
        }.value
    }
}
