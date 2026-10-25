import AVFoundation
import Observation

/// Records from the microphone — the fallback for music playing on another device or speaker,
/// or from an app whose audio can't be captured directly.
@Observable
@MainActor
final class MicRecorder {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var level: Float = 0

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var timer: Timer?

    func start() async throws {
        guard !isRecording else { return }
        #if os(iOS)
        guard await AVAudioApplication.requestRecordPermission() else { throw RecorderError.permissionDenied }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)
        #else
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw RecorderError.permissionDenied }
        #endif

        let url = StorageLocation.capturesInProgress.appendingPathComponent("mic-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw RecorderError.couldNotStart }
        self.recorder = recorder
        isRecording = true
        elapsed = 0

        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops recording and returns the finished file, or nil if nothing was recorded.
    func stop() -> URL? {
        guard let recorder else { return nil }
        let url = recorder.url
        let recordedTime = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        timer?.invalidate()
        timer = nil
        isRecording = false
        level = 0
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        #endif
        guard recordedTime > 0.2 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }

    private func tick() {
        guard let recorder else { return }
        recorder.updateMeters()
        elapsed = recorder.currentTime
        level = pow(10, recorder.averagePower(forChannel: 0) / 20)
    }

    enum RecorderError: LocalizedError {
        case permissionDenied
        case couldNotStart

        var errorDescription: String? {
            switch self {
            case .permissionDenied: "Microphone access is off. Turn it on for Slow Down Buddy in Settings › Privacy & Security › Microphone."
            case .couldNotStart: "Recording couldn't start."
            }
        }
    }
}
