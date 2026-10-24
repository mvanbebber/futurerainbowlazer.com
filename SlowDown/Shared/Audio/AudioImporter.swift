import AVFoundation

/// Copies audio into the library, or extracts the audio track from video and other containers.
///
/// Files Core Audio can read directly (WAV, AIFF, CAF, M4A/AAC/ALAC, MP3, FLAC — including most Voice
/// Memos) are copied untouched. Everything else AVFoundation can decode — MP4, MOV,
/// M4V, Voice Memos' QuickTime audio (.qta), 3GP, … — is decoded and re-encoded as AAC.
enum AudioImporter {
    static let directExtensions: Set<String> = [
        "wav", "wave", "aif", "aiff", "aifc", "caf", "m4a", "m4r", "aac", "mp3", "flac", "alac",
    ]

    struct Result {
        let fileName: String
        let duration: TimeInterval
    }

    static func importFile(at source: URL, into folder: URL) async throws -> Result {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        let ext = source.pathExtension.lowercased()
        let baseName = UUID().uuidString

        if directExtensions.contains(ext), (try? AVAudioFile(forReading: source)) != nil {
            let destination = folder.appendingPathComponent(baseName).appendingPathExtension(ext)
            try FileManager.default.copyItem(at: source, to: destination)
            return Result(fileName: destination.lastPathComponent, duration: try duration(of: destination))
        }

        let destination = folder.appendingPathComponent(baseName).appendingPathExtension("m4a")
        do {
            try await extractAudio(from: source, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return Result(fileName: destination.lastPathComponent, duration: try duration(of: destination))
    }

    static func duration(of url: URL) throws -> TimeInterval {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }

    /// Decodes the first audio track of any AVFoundation-readable file into an AAC `.m4a`.
    static func extractAudio(from source: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ImportError.noAudioTrack
        }
        try await Task.detached(priority: .userInitiated) {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { throw ImportError.unreadable }
            reader.add(output)
            guard reader.startReading() else { throw reader.error ?? ImportError.unreadable }

            let writer = CaptureFileWriter(url: destination)
            while let sampleBuffer = output.copyNextSampleBuffer() {
                if Task.isCancelled {
                    reader.cancelReading()
                    throw CancellationError()
                }
                writer.append(sampleBuffer)
            }
            writer.finish()
            if reader.status == .failed { throw reader.error ?? ImportError.unreadable }
            if let error = writer.lastError { throw error }
            if writer.framesWritten == 0 { throw ImportError.unreadable }
        }.value
    }

    enum ImportError: LocalizedError {
        case noAudioTrack
        case unreadable

        var errorDescription: String? {
            switch self {
            case .noAudioTrack: "The file doesn't contain any audio."
            case .unreadable: "The file's audio couldn't be decoded."
            }
        }
    }
}
