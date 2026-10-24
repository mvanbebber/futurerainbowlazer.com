import AVFoundation

/// Renders mono, single-channel and "karaoke" (center-cancelled) versions of a stereo file.
///
/// The output keeps the source's sample rate, channel count and length so playback can switch between
/// versions at the same frame position.
enum ChannelProcessor {
    static func file(for source: URL, mode: ChannelMode) async throws -> URL {
        guard mode != .stereo else { return source }
        let name = "\(source.deletingPathExtension().lastPathComponent)-\(mode.rawValue).caf"
        let destination = StorageLocation.processedCache.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        try await Task.detached(priority: .userInitiated) {
            try render(source: source, destination: destination, mode: mode)
        }.value
        return destination
    }

    /// Removes cached renders of a library file.
    static func removeCache(for source: URL) {
        let base = source.deletingPathExtension().lastPathComponent
        for mode in ChannelMode.allCases where mode != .stereo {
            let url = StorageLocation.processedCache.appendingPathComponent("\(base)-\(mode.rawValue).caf")
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func render(source: URL, destination: URL, mode: ChannelMode) throws {
        let input = try AVAudioFile(forReading: source)
        let inFormat = input.processingFormat
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent("\(UUID().uuidString)-partial.caf")
        defer { try? FileManager.default.removeItem(at: temporary) }

        do {
            let output = try AVAudioFile(
                forWriting: temporary, settings: inFormat.settings,
                commonFormat: .pcmFormatFloat32, interleaved: false)
            let capacity: AVAudioFrameCount = 65_536
            guard let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: capacity),
                  let outBuffer = AVAudioPCMBuffer(pcmFormat: output.processingFormat, frameCapacity: capacity)
            else { throw AudioImporter.ImportError.unreadable }

            while input.framePosition < input.length {
                try input.read(into: inBuffer)
                let frames = Int(inBuffer.frameLength)
                if frames == 0 { break }
                process(inBuffer, into: outBuffer, frames: frames, mode: mode)
                try output.write(from: outBuffer)
            }
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    private static func process(_ input: AVAudioPCMBuffer, into output: AVAudioPCMBuffer, frames: Int, mode: ChannelMode) {
        guard let src = input.floatChannelData, let dst = output.floatChannelData else { return }
        let inChannels = Int(input.format.channelCount)
        let outChannels = Int(output.format.channelCount)
        output.frameLength = AVAudioFrameCount(frames)

        let left = src[0]
        let right = inChannels > 1 ? src[1] : src[0]
        for i in 0..<frames {
            let value: Float
            switch mode {
            case .stereo: value = left[i]
            case .mono: value = (left[i] + right[i]) * 0.5
            case .left: value = left[i]
            case .right: value = right[i]
            // Vocals, bass and kick are usually mixed dead center; subtracting the channels removes them.
            case .karaoke: value = (left[i] - right[i]) * 0.7
            }
            for ch in 0..<outChannels { dst[ch][i] = value }
        }
    }
}
