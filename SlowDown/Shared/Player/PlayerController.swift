import Foundation
import Observation

/// Connects one recording to the playback engine: applies its saved settings, edits its markers and loops,
/// and writes every change back to the library.
@Observable
@MainActor
final class PlayerController {
    let engine = PlaybackEngine()
    private(set) var recording: Recording
    private(set) var waveform: WaveformData?
    private(set) var isLoaded = false
    var errorMessage: String?

    @ObservationIgnored private let library: Library
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    static let speedRange: ClosedRange<Double> = 0.25...2.0
    static let semitoneRange: ClosedRange<Int> = -24...24

    init(recording: Recording, library: Library) {
        self.recording = recording
        self.library = library
    }

    var audioURL: URL { library.fileURL(for: recording) }

    func load() async {
        do {
            try engine.load(url: audioURL)
        } catch {
            errorMessage = "The audio couldn't be opened: \(error.localizedDescription)"
            return
        }
        let settings = recording.settings
        engine.speed = settings.speed
        engine.pitchCents = settings.pitchCents
        engine.volume = settings.volume
        for (band, gain) in settings.eqGains.enumerated() {
            engine.setEQGain(band: band, gain: gain)
        }
        syncLoop()
        engine.seek(to: min(settings.lastPosition, engine.duration))
        if abs(recording.duration - engine.duration) > 0.01 {
            recording.duration = engine.duration
            scheduleSave()
        }
        isLoaded = true
        if settings.channelMode != .stereo {
            await engine.setChannelMode(settings.channelMode)
        }
        waveform = try? await WaveformData.load(url: audioURL)
    }

    func close() {
        recording.settings.lastPosition = engine.currentTime
        engine.shutdown()
        saveNow()
    }

    // MARK: Speed, pitch, volume, EQ

    var speed: Double {
        get { recording.settings.speed }
        set {
            let value = (newValue * 100).rounded() / 100
            recording.settings.speed = min(max(value, Self.speedRange.lowerBound), Self.speedRange.upperBound)
            engine.speed = recording.settings.speed
            scheduleSave()
        }
    }

    var semitones: Int {
        get { recording.settings.semitones }
        set {
            recording.settings.semitones = min(max(newValue, Self.semitoneRange.lowerBound), Self.semitoneRange.upperBound)
            engine.pitchCents = recording.settings.pitchCents
            scheduleSave()
        }
    }

    var cents: Double {
        get { recording.settings.cents }
        set {
            recording.settings.cents = min(max(newValue.rounded(), -50), 50)
            engine.pitchCents = recording.settings.pitchCents
            scheduleSave()
        }
    }

    var volume: Double {
        get { recording.settings.volume }
        set {
            recording.settings.volume = min(max(newValue, 0), 1)
            engine.volume = recording.settings.volume
            scheduleSave()
        }
    }

    var channelMode: ChannelMode {
        get { recording.settings.channelMode }
        set {
            recording.settings.channelMode = newValue
            scheduleSave()
            Task { await engine.setChannelMode(newValue) }
        }
    }

    func eqGain(_ band: Int) -> Double {
        recording.settings.eqGains.indices.contains(band) ? recording.settings.eqGains[band] : 0
    }

    func setEQGain(_ band: Int, _ gain: Double) {
        guard recording.settings.eqGains.indices.contains(band) else { return }
        recording.settings.eqGains[band] = gain.rounded()
        engine.setEQGain(band: band, gain: gain.rounded())
        scheduleSave()
    }

    func applyEQPreset(_ gains: [Double]) {
        for (band, gain) in gains.enumerated() { setEQGain(band, gain) }
    }

    func resetPitch() {
        semitones = 0
        cents = 0
    }

    // MARK: Transport

    func togglePlay() { engine.togglePlay() }

    func seek(to time: TimeInterval) {
        engine.seek(to: min(max(time, 0), engine.duration))
    }

    func skip(by seconds: TimeInterval) {
        seek(to: engine.currentTime + seconds)
    }

    func goToStart() {
        seek(to: loopActive ? (recording.settings.loopStart ?? 0) : 0)
    }

    func previousMarker() {
        // A small grace period lets repeated presses walk backwards while playing.
        let now = engine.currentTime - (engine.isPlaying ? 0.5 : 0.01)
        let target = recording.markers.last(where: { $0.time < now })?.time ?? 0
        seek(to: target)
    }

    func nextMarker() {
        let now = engine.currentTime + 0.01
        if let target = recording.markers.first(where: { $0.time > now })?.time {
            seek(to: target)
        }
    }

    // MARK: Loop

    var loopStart: TimeInterval? { recording.settings.loopStart }
    var loopEnd: TimeInterval? { recording.settings.loopEnd }
    var loopActive: Bool { recording.settings.loopEnabled && loopStart != nil && loopEnd != nil }

    var loopEnabled: Bool {
        get { recording.settings.loopEnabled }
        set {
            if newValue, loopStart == nil || loopEnd == nil {
                // No region yet: loop the bar/section the playhead is in, or the next 4 seconds.
                let (start, end) = regionAroundPlayhead()
                recording.settings.loopStart = start
                recording.settings.loopEnd = end
            }
            recording.settings.loopEnabled = newValue
            syncLoop()
            scheduleSave()
        }
    }

    func setLoop(start: TimeInterval, end: TimeInterval, seekToStart: Bool = true) {
        let a = max(0, min(start, end))
        let b = min(engine.duration, max(start, end))
        guard b - a >= 0.05 else { return }
        recording.settings.loopStart = a
        recording.settings.loopEnd = b
        recording.settings.loopEnabled = true
        syncLoop()
        if seekToStart { seek(to: a) }
        scheduleSave()
    }

    func setLoopStartAtPlayhead() {
        let now = engine.currentTime
        let end = if let loopEnd, loopEnd > now + 0.05 { loopEnd } else { min(engine.duration, now + 4) }
        setLoop(start: now, end: end, seekToStart: false)
    }

    func setLoopEndAtPlayhead() {
        let now = engine.currentTime
        let start = if let loopStart, loopStart < now - 0.05 { loopStart } else { max(0, now - 4) }
        setLoop(start: start, end: now, seekToStart: true)
    }

    func nudgeLoop(start: Bool, by delta: TimeInterval) {
        guard let a = loopStart, let b = loopEnd else { return }
        if start {
            setLoop(start: min(a + delta, b - 0.05), end: b, seekToStart: true)
        } else {
            setLoop(start: a, end: max(b + delta, a + 0.05), seekToStart: false)
        }
    }

    func clearLoop() {
        recording.settings.loopStart = nil
        recording.settings.loopEnd = nil
        recording.settings.loopEnabled = false
        syncLoop()
        scheduleSave()
    }

    func saveCurrentLoop(named name: String) {
        guard let a = loopStart, let b = loopEnd else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "Loop \(recording.loops.count + 1)" : trimmed
        recording.loops.append(SavedLoop(name: title, start: a, end: b))
        scheduleSave()
    }

    func activate(_ loop: SavedLoop) {
        setLoop(start: loop.start, end: loop.end)
    }

    func deleteLoop(_ id: SavedLoop.ID) {
        recording.loops.removeAll { $0.id == id }
        scheduleSave()
    }

    func renameLoop(_ id: SavedLoop.ID, to name: String) {
        guard let index = recording.loops.firstIndex(where: { $0.id == id }) else { return }
        recording.loops[index].name = name
        scheduleSave()
    }

    private func syncLoop() {
        if loopActive, let a = loopStart, let b = loopEnd {
            engine.setLoop(a...b)
        } else {
            engine.setLoop(nil)
        }
    }

    private func regionAroundPlayhead() -> (TimeInterval, TimeInterval) {
        let now = engine.currentTime
        let start = recording.markers.last(where: { $0.time <= now })?.time ?? now
        let end = recording.markers.first(where: { $0.time > now })?.time ?? min(engine.duration, now + 4)
        return (start, max(end, start + 0.05))
    }

    // MARK: Markers

    func addMarker(_ kind: Marker.Kind, at time: TimeInterval? = nil) {
        let position = time ?? engine.currentTime
        // Don't stack duplicates when a key is pressed twice.
        if recording.markers.contains(where: { abs($0.time - position) < 0.02 && $0.kind == kind }) { return }
        recording.markers.append(Marker(time: position, kind: kind))
        recording.markers.sort { $0.time < $1.time }
        scheduleSave()
    }

    func renameMarker(_ id: Marker.ID, to label: String) {
        guard let index = recording.markers.firstIndex(where: { $0.id == id }) else { return }
        recording.markers[index].label = label
        scheduleSave()
    }

    func moveMarkerToPlayhead(_ id: Marker.ID) {
        guard let index = recording.markers.firstIndex(where: { $0.id == id }) else { return }
        recording.markers[index].time = engine.currentTime
        recording.markers.sort { $0.time < $1.time }
        scheduleSave()
    }

    func deleteMarker(_ id: Marker.ID) {
        recording.markers.removeAll { $0.id == id }
        scheduleSave()
    }

    /// Loops from a marker to the next marker of the same or a higher level (e.g. a whole section).
    func loopFrom(_ marker: Marker) {
        let levels: [Marker.Kind] = [.section, .measure, .beat]
        let rank = levels.firstIndex(of: marker.kind) ?? 0
        let next = recording.markers.first { other in
            other.time > marker.time + 0.01 && (levels.firstIndex(of: other.kind) ?? 0) <= rank
        }
        setLoop(start: marker.time, end: next?.time ?? engine.duration)
    }

    func label(for marker: Marker) -> String {
        recording.label(for: marker)
    }

    // MARK: Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        library.update(recording)
    }
}
