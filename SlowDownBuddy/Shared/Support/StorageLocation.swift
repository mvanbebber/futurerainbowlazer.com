import Foundation

/// Where Slow Down Buddy keeps its files.
///
/// On iOS everything lives in the shared App Group container so the ReplayKit
/// broadcast extension can drop finished captures where the app will find them.
/// On macOS the (sandboxed) Application Support folder is used.
enum StorageLocation {
    static let appGroupID = "group.com.futurerainbowlazer.slowdownbuddy"

    /// Darwin notification posted by the broadcast extension when a capture is ready.
    static let captureFinishedNotification = "com.futurerainbowlazer.slowdownbuddy.captureFinished"

    static var root: URL {
        #if os(iOS)
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return container
        }
        #endif
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return directory(support.appendingPathComponent("SlowDownBuddy", isDirectory: true))
    }

    /// Imported and captured recordings.
    static var library: URL { directory(root.appendingPathComponent("Library", isDirectory: true)) }

    /// Finished captures waiting to be added to the library.
    static var captures: URL { directory(root.appendingPathComponent("Captures", isDirectory: true)) }

    /// Captures that are still being written.
    static var capturesInProgress: URL { directory(captures.appendingPathComponent("InProgress", isDirectory: true)) }

    /// Re-rendered audio (mono / left / right / karaoke) that can be regenerated at any time.
    static var processedCache: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return directory(caches.appendingPathComponent("Processed", isDirectory: true))
    }

    @discardableResult
    private static func directory(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Returns `url` if nothing exists there, otherwise "name 2.ext", "name 3.ext", …
    static func uniqueURL(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let folder = url.deletingLastPathComponent()
        var n = 2
        while true {
            let candidate = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    /// A filesystem-safe title such as "Screen Capture 2026-10-24 at 09.35.12".
    static func timestampedName(_ prefix: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(prefix) \(formatter.string(from: date))"
    }
}
