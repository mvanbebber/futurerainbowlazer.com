import Foundation
import Observation

/// The list of recordings and their practice settings, persisted as JSON next to the audio files.
@Observable
@MainActor
final class Library {
    private(set) var recordings: [Recording] = []
    private(set) var importingCount = 0
    var errorMessage: String?

    @ObservationIgnored private let indexURL = StorageLocation.root.appendingPathComponent("library.json")

    static let audioExtensions: Set<String> = AudioImporter.directExtensions.union(["mp4", "mov", "m4v", "qta", "3gp"])

    init() {
        load()
        ingestPendingCaptures()
        #if os(iOS)
        observeBroadcastExtension()
        #endif
    }

    func recording(with id: Recording.ID) -> Recording? {
        recordings.first { $0.id == id }
    }

    func fileURL(for recording: Recording) -> URL {
        StorageLocation.library.appendingPathComponent(recording.fileName)
    }

    // MARK: Adding

    /// Imports files picked or dropped by the user and returns the last one that succeeded.
    @discardableResult
    func importFiles(_ urls: [URL]) async -> Recording? {
        var last: Recording?
        for url in urls {
            do {
                last = try await importFile(url)
            } catch {
                errorMessage = "Couldn't import “\(url.lastPathComponent)”: \(error.localizedDescription)"
            }
        }
        return last
    }

    func importFile(_ url: URL) async throws -> Recording {
        importingCount += 1
        defer { importingCount -= 1 }
        let result = try await AudioImporter.importFile(at: url, into: StorageLocation.library)
        let recording = Recording(
            title: url.deletingPathExtension().lastPathComponent,
            fileName: result.fileName,
            duration: result.duration)
        recordings.insert(recording, at: 0)
        save()
        return recording
    }

    /// Moves a finished capture or microphone recording into the library.
    @discardableResult
    func addCapture(at url: URL, title: String, source: Recording.Source) throws -> Recording {
        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
        let destination = StorageLocation.library.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try FileManager.default.moveItem(at: url, to: destination)
        let duration = (try? AudioImporter.duration(of: destination)) ?? 0
        let recording = Recording(
            title: title, fileName: destination.lastPathComponent, duration: duration, source: source)
        recordings.insert(recording, at: 0)
        save()
        return recording
    }

    /// Adds captures the iOS broadcast extension finished while the app was in the background.
    func ingestPendingCaptures() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: StorageLocation.captures, includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey])
        else { return }
        let sorted = items.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a < b
        }
        for url in sorted {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard !isDirectory, Self.audioExtensions.contains(url.pathExtension.lowercased()) else { continue }
            do {
                try addCapture(at: url, title: url.deletingPathExtension().lastPathComponent, source: .systemCapture)
            } catch {
                errorMessage = "Couldn't add a screen capture: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Editing

    func update(_ recording: Recording) {
        guard let index = recordings.firstIndex(where: { $0.id == recording.id }) else { return }
        guard recordings[index] != recording else { return }
        recordings[index] = recording
        save()
    }

    func rename(_ id: Recording.ID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = recordings.firstIndex(where: { $0.id == id }) else { return }
        recordings[index].title = trimmed
        save()
    }

    func delete(_ id: Recording.ID) {
        guard let index = recordings.firstIndex(where: { $0.id == id }) else { return }
        let url = fileURL(for: recordings[index])
        ChannelProcessor.removeCache(for: url)
        try? FileManager.default.removeItem(at: url)
        recordings.remove(at: index)
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        do {
            let decoded = try JSONDecoder().decode([Recording].self, from: data)
            recordings = decoded.filter { FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
        } catch {
            errorMessage = "The library index couldn't be read: \(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(recordings).write(to: indexURL, options: .atomic)
        } catch {
            errorMessage = "The library couldn't be saved: \(error.localizedDescription)"
        }
    }

    #if os(iOS)
    private func observeBroadcastExtension() {
        let callback: CFNotificationCallback = { _, observer, _, _, _ in
            guard let observer else { return }
            let library = Unmanaged<Library>.fromOpaque(observer).takeUnretainedValue()
            Task { @MainActor in library.ingestPendingCaptures() }
        }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            callback,
            StorageLocation.captureFinishedNotification as CFString,
            nil,
            .deliverImmediately)
    }
    #endif
}
