import AVFoundation
import ReplayKit

/// ReplayKit broadcast upload extension: writes the audio of whatever app is playing (YouTube, Spotify, …)
/// to the shared App Group, where Slow Down Buddy imports it. Video frames and the microphone are ignored.
final class SampleHandler: RPBroadcastSampleHandler {
    private let queue = DispatchQueue(label: "com.futurerainbowlazer.slowdownbuddy.broadcast")
    private var writer: CaptureFileWriter?
    private var startDate = Date()

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        startDate = Date()
        let url = StorageLocation.capturesInProgress.appendingPathComponent("\(UUID().uuidString).m4a")
        queue.sync { writer = CaptureFileWriter(url: url) }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .audioApp else { return }
        queue.sync { _ = writer?.append(sampleBuffer) }
    }

    override func broadcastFinished() {
        queue.sync { finishRecording() }
    }

    private func finishRecording() {
        guard let writer else { return }
        writer.finish()
        self.writer = nil

        guard writer.framesWritten > 0 else {
            try? FileManager.default.removeItem(at: writer.url)
            return
        }
        let name = StorageLocation.timestampedName("Screen Capture", date: startDate)
        let destination = StorageLocation.uniqueURL(
            StorageLocation.captures.appendingPathComponent(name).appendingPathExtension("m4a"))
        do {
            try FileManager.default.moveItem(at: writer.url, to: destination)
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName(StorageLocation.captureFinishedNotification as CFString),
                nil, nil, true)
        } catch {
            NSLog("Slow Down Buddy capture couldn't be saved: \(error)")
        }
    }
}
