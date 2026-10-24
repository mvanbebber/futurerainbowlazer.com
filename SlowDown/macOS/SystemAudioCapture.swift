import AVFoundation
import Observation
import ScreenCaptureKit

/// Records the audio output of one app (Spotify, Safari/Chrome playing YouTube, Music, …) or of the whole Mac,
/// using ScreenCaptureKit. Requires the "Screen & System Audio Recording" permission.
@Observable
@MainActor
final class SystemAudioCapture {
    struct AppChoice: Identifiable, Hashable {
        let id: String
        let name: String
    }

    private(set) var apps: [AppChoice] = []
    /// nil records everything the Mac plays (except SlowDown itself).
    var selectedAppID: String?
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var level: Float = 0
    var errorMessage: String?

    @ObservationIgnored private var content: SCShareableContent?
    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var sink: CaptureSink?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var startDate = Date()

    /// Apps people most often want to capture from, listed first.
    private static let favourites = [
        "com.spotify.client", "com.google.Chrome", "com.apple.Safari", "org.mozilla.firefox",
        "com.microsoft.edgemac", "company.thebrowser.Browser", "com.brave.Browser", "com.apple.Music",
        "com.apple.podcasts", "com.apple.TV",
    ]

    var selectedAppName: String? {
        apps.first { $0.id == selectedAppID }?.name
    }

    func refreshApps() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            self.content = content
            let me = Bundle.main.bundleIdentifier
            var seen = Set<String>()
            let choices = content.applications.compactMap { app -> AppChoice? in
                let id = app.bundleIdentifier
                guard !id.isEmpty, id != me, !app.applicationName.isEmpty, seen.insert(id).inserted else { return nil }
                return AppChoice(id: id, name: app.applicationName)
            }
            apps = choices.sorted { a, b in
                let ra = Self.favourites.firstIndex(of: a.id) ?? Int.max
                let rb = Self.favourites.firstIndex(of: b.id) ?? Int.max
                return ra != rb ? ra < rb : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            if selectedAppID == nil || !apps.contains(where: { $0.id == selectedAppID }) {
                selectedAppID = apps.first { Self.favourites.contains($0.id) }?.id
            }
            errorMessage = nil
        } catch {
            errorMessage = Self.permissionHint
        }
    }

    func start() async {
        guard !isRecording else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            self.content = content
            guard let display = content.displays.first else { throw CaptureError.noDisplay }

            let filter: SCContentFilter
            if let id = selectedAppID, let app = content.applications.first(where: { $0.bundleIdentifier == id }) {
                filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
            } else {
                let me = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
                filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
            }

            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48_000
            config.channelCount = 2
            // Video is required by the API but unused: keep it tiny and slow.
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 2)
            config.showsCursor = false

            let url = StorageLocation.capturesInProgress.appendingPathComponent("mac-\(UUID().uuidString).m4a")
            let sink = CaptureSink(writer: CaptureFileWriter(url: url))
            sink.onLevel = { [weak self] level in
                Task { @MainActor in self?.level = level }
            }
            sink.onStop = { [weak self] error in
                Task { @MainActor in
                    self?.errorMessage = "Capture stopped: \(error.localizedDescription)"
                }
            }
            let stream = SCStream(filter: filter, configuration: config, delegate: sink)
            try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: sink.queue)
            try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
            try await stream.startCapture()

            self.sink = sink
            self.stream = stream
            isRecording = true
            errorMessage = nil
            startDate = Date()
            elapsed = 0
            let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.elapsed = Date().timeIntervalSince(self.startDate)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } catch {
            errorMessage = (error as? CaptureError)?.errorDescription ?? "\(Self.permissionHint)\n\n(\(error.localizedDescription))"
        }
    }

    /// Stops recording and returns the finished file, or nil if no audio arrived.
    func stop() async -> URL? {
        guard isRecording, let stream, let sink else { return nil }
        try? await stream.stopCapture()
        timer?.invalidate()
        timer = nil
        isRecording = false
        level = 0
        self.stream = nil
        self.sink = nil
        let (url, frames) = sink.finish()
        guard frames > 0 else {
            try? FileManager.default.removeItem(at: url)
            errorMessage = "No audio was captured. Make sure the app was playing sound, and that it's the app selected above."
            return nil
        }
        return url
    }

    static let permissionHint = "SlowDown needs permission to record system audio. Open System Settings › Privacy & Security › Screen & System Audio Recording, turn SlowDown on, then quit and reopen SlowDown."

    enum CaptureError: LocalizedError {
        case noDisplay

        var errorDescription: String? { "No display is available to capture from." }
    }
}

/// Receives ScreenCaptureKit buffers on a background queue and writes the audio.
private final class CaptureSink: NSObject, SCStreamOutput, SCStreamDelegate {
    let queue = DispatchQueue(label: "com.futurerainbowlazer.slowdown.capture")
    private let writer: CaptureFileWriter
    private var lastLevelUpdate = Date.distantPast
    var onLevel: ((Float) -> Void)?
    var onStop: ((Error) -> Void)?

    init(writer: CaptureFileWriter) {
        self.writer = writer
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let peak = writer.append(sampleBuffer) else { return }
        let now = Date()
        if now.timeIntervalSince(lastLevelUpdate) > 0.08 {
            lastLevelUpdate = now
            onLevel?(peak)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStop?(error)
    }

    func finish() -> (URL, AVAudioFramePosition) {
        queue.sync {
            writer.finish()
            return (writer.url, writer.framesWritten)
        }
    }
}
