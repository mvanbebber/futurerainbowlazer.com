import AVFoundation
import Accelerate
import CoreMedia

/// Writes PCM audio — from ScreenCaptureKit, ReplayKit or an `AVAssetReader` — to an AAC `.m4a` file.
///
/// The output format is chosen from the first buffer (mono or stereo, at most 48 kHz). Later buffers in a
/// different format (ReplayKit sometimes changes sample rate or delivers big-endian Int16) are converted.
/// Not thread-safe: call it from one serial queue.
final class CaptureFileWriter {
    let url: URL
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private(set) var framesWritten: AVAudioFramePosition = 0
    private(set) var lastError: Error?

    init(url: URL) {
        self.url = url
    }

    var duration: TimeInterval {
        guard let file else { return 0 }
        return Double(framesWritten) / file.processingFormat.sampleRate
    }

    /// Appends a CMSampleBuffer containing linear PCM. Returns the peak level (0…1) of the written audio.
    @discardableResult
    func append(_ sampleBuffer: CMSampleBuffer) -> Float? {
        guard let buffer = Self.pcmBuffer(from: sampleBuffer) else { return nil }
        return append(buffer)
    }

    @discardableResult
    func append(_ input: AVAudioPCMBuffer) -> Float? {
        guard input.frameLength > 0 else { return nil }
        do {
            if file == nil { try open(matching: input.format) }
            guard let file else { return nil }
            let output = try convert(input, to: file.processingFormat)
            guard output.frameLength > 0 else { return nil }
            try file.write(from: output)
            framesWritten += AVAudioFramePosition(output.frameLength)
            return Self.peak(of: output)
        } catch {
            lastError = error
            return nil
        }
    }

    /// Closes the file. `AVAudioFile` finalises the container when it is released.
    func finish() {
        file = nil
        converter = nil
    }

    private func open(matching format: AVAudioFormat) throws {
        let channels: AVAudioChannelCount = format.channelCount >= 2 ? 2 : 1
        let sampleRate = min(format.sampleRate, 48_000)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: channels == 2 ? 256_000 : 128_000,
        ]
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    private func convert(_ input: AVAudioPCMBuffer, to target: AVAudioFormat) throws -> AVAudioPCMBuffer {
        if input.format == target { return input }
        if converter == nil || converter?.inputFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: target)
            converter?.downmix = true
        }
        guard let converter else { throw CaptureWriterError.unsupportedFormat }

        let ratio = target.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw CaptureWriterError.unsupportedFormat
        }
        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        if status == .error { throw conversionError ?? CaptureWriterError.unsupportedFormat }
        return output
    }

    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard CMSampleBufferIsValid(sampleBuffer),
              let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)
        else { return nil }
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0 else { return nil }

        let format: AVAudioFormat?
        var layoutSize = 0
        if let layout = CMAudioFormatDescriptionGetChannelLayout(description, sizeOut: &layoutSize) {
            format = AVAudioFormat(streamDescription: asbd, channelLayout: AVAudioChannelLayout(layout: layout))
        } else {
            format = AVAudioFormat(streamDescription: asbd)
        }
        guard let format,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }

    static func peak(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        var peak: Float = 0
        for ch in 0..<Int(buffer.format.channelCount) {
            var channelPeak: Float = 0
            vDSP_maxmgv(channels[ch], buffer.stride, &channelPeak, vDSP_Length(buffer.frameLength))
            peak = max(peak, channelPeak)
        }
        return min(peak, 1)
    }
}

enum CaptureWriterError: LocalizedError {
    case unsupportedFormat

    var errorDescription: String? { "The captured audio format isn't supported." }
}
