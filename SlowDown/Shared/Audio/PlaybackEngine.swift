import AVFoundation
import Observation

/// Plays one audio file with independent speed and pitch, a 5-band EQ, channel modes and gapless A–B looping.
///
/// Signal chain: `AVAudioPlayerNode` → `AVAudioUnitTimePitch` → `AVAudioUnitEQ` → main mixer.
/// Audio is scheduled in segments so the exact file position is always known, even while looping
/// at a changed speed.
@Observable
@MainActor
final class PlaybackEngine {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var channelCount: Int = 2
    private(set) var channelMode: ChannelMode = .stereo
    private(set) var isProcessingChannels = false
    var errorMessage: String?

    /// Playback rate, 0.25…2.0. Pitch is unaffected.
    var speed: Double = 1 {
        didSet { timePitch.rate = Float(speed) }
    }

    /// Transposition in cents (100 = one semitone). Speed is unaffected.
    var pitchCents: Double = 0 {
        didSet { timePitch.pitch = Float(pitchCents) }
    }

    var volume: Double = 1 {
        didSet { engine.mainMixerNode.outputVolume = Float(volume) }
    }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private let timePitch = AVAudioUnitTimePitch()
    @ObservationIgnored private let eq = AVAudioUnitEQ(numberOfBands: EQBand.all.count)

    @ObservationIgnored private var sourceURL: URL?
    @ObservationIgnored private var file: AVAudioFile?
    @ObservationIgnored private var sampleRate: Double = 44_100
    @ObservationIgnored private var lengthFrames: AVAudioFramePosition = 0
    @ObservationIgnored private var loopFrames: Range<AVAudioFramePosition>?

    /// Frame position while paused, or where the current scheduling run started.
    @ObservationIgnored private var anchorFrame: AVAudioFramePosition = 0
    @ObservationIgnored private var segments: [Segment] = []
    @ObservationIgnored private var scheduledFrames: AVAudioFramePosition = 0
    /// Bumped whenever scheduled audio is thrown away, so stale completion handlers are ignored.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var configObserver: NSObjectProtocol?

    private struct Segment {
        let playerStart: AVAudioFramePosition
        let fileStart: AVAudioFramePosition
        let length: AVAudioFrameCount
    }

    init() {
        engine.attach(player)
        engine.attach(timePitch)
        engine.attach(eq)
        for (band, config) in zip(eq.bands, EQBand.all) {
            switch config.shape {
            case .lowShelf: band.filterType = .lowShelf
            case .highShelf: band.filterType = .highShelf
            case .peak:
                band.filterType = .parametric
                band.bandwidth = 1.2
            }
            band.frequency = config.frequency
            band.gain = 0
            band.bypass = false
        }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleConfigurationChange() }
        }
    }

    // MARK: Loading

    func load(url: URL) throws {
        stop()
        let newFile = try AVAudioFile(forReading: url)
        let format = newFile.processingFormat
        file = newFile
        sourceURL = url
        sampleRate = format.sampleRate
        lengthFrames = newFile.length
        duration = Double(lengthFrames) / sampleRate
        channelCount = Int(format.channelCount)
        channelMode = .stereo
        anchorFrame = 0
        currentTime = 0

        engine.stop()
        engine.disconnectNodeOutput(player)
        engine.disconnectNodeOutput(timePitch)
        engine.disconnectNodeOutput(eq)
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
    }

    /// Switches between stereo, mono, left, right and karaoke. Non-stereo modes are rendered to a cache file once.
    func setChannelMode(_ mode: ChannelMode) async {
        guard let sourceURL, mode != channelMode else { return }
        guard channelCount >= 2 || mode == .stereo else { return }
        isProcessingChannels = true
        defer { isProcessingChannels = false }
        do {
            let url = try await ChannelProcessor.file(for: sourceURL, mode: mode)
            let newFile = try AVAudioFile(forReading: url)
            guard newFile.processingFormat.sampleRate == sampleRate,
                  newFile.processingFormat.channelCount == AVAudioChannelCount(channelCount)
            else { return }
            let frame = currentFrame()
            let wasPlaying = isPlaying
            if wasPlaying { discardScheduledAudio() }
            file = newFile
            channelMode = mode
            anchorFrame = frame
            if wasPlaying { scheduleAndPlay(from: frame) }
        } catch {
            errorMessage = "Couldn't switch to \(mode.title): \(error.localizedDescription)"
        }
    }

    func setEQGain(band: Int, gain: Double) {
        guard eq.bands.indices.contains(band) else { return }
        eq.bands[band].gain = Float(gain)
    }

    // MARK: Transport

    func play() {
        guard file != nil, !isPlaying else { return }
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            errorMessage = "Audio output couldn't start: \(error.localizedDescription)"
            return
        }
        var start = anchorFrame
        if loopFrames == nil, start >= lengthFrames - 1 { start = 0 }
        scheduleAndPlay(from: start)
    }

    func pause() {
        guard isPlaying else { return }
        let frame = currentFrame()
        discardScheduledAudio()
        anchorFrame = frame
        isPlaying = false
        stopTimer()
        currentTime = time(of: frame)
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func stop() {
        discardScheduledAudio()
        isPlaying = false
        stopTimer()
    }

    /// Stops playback and releases the audio hardware. Call when the player goes away.
    func shutdown() {
        stop()
        engine.stop()
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
    }

    func seek(to time: TimeInterval) {
        let frame = clampFrame(AVAudioFramePosition(time * sampleRate))
        if isPlaying {
            discardScheduledAudio()
            scheduleAndPlay(from: frame)
        } else {
            anchorFrame = frame
        }
        currentTime = self.time(of: frame)
    }

    /// Sets (or clears) the A–B loop. Playback that starts before the loop runs into it and repeats it;
    /// playback that starts after it plays on to the end.
    func setLoop(_ range: ClosedRange<TimeInterval>?) {
        let newFrames: Range<AVAudioFramePosition>? = range.flatMap { range in
            let start = clampFrame(AVAudioFramePosition(range.lowerBound * sampleRate))
            let end = clampFrame(AVAudioFramePosition(range.upperBound * sampleRate))
            return end - start > AVAudioFramePosition(sampleRate * 0.02) ? start..<end : nil
        }
        guard newFrames != loopFrames else { return }
        loopFrames = newFrames
        if isPlaying {
            let frame = currentFrame()
            discardScheduledAudio()
            scheduleAndPlay(from: frame)
        }
    }

    // MARK: Scheduling

    private func scheduleAndPlay(from frame: AVAudioFramePosition) {
        segments.removeAll()
        scheduledFrames = 0
        anchorFrame = frame
        let gen = generation
        if let loop = loopFrames, frame < loop.upperBound {
            schedule(frame..<loop.upperBound, looping: true, generation: gen)
            schedule(loop, looping: true, generation: gen)
            schedule(loop, looping: true, generation: gen)
        } else {
            schedule(frame..<lengthFrames, looping: false, generation: gen)
        }
        player.play()
        isPlaying = true
        startTimer()
    }

    private func schedule(_ range: Range<AVAudioFramePosition>, looping: Bool, generation gen: Int) {
        guard let file, range.count > 0 else {
            if !looping { Task { @MainActor in self.segmentFinished(generation: gen, looping: false) } }
            return
        }
        let count = AVAudioFrameCount(range.count)
        segments.append(Segment(playerStart: scheduledFrames, fileStart: range.lowerBound, length: count))
        if segments.count > 8 { segments.removeFirst(segments.count - 8) }
        scheduledFrames += AVAudioFramePosition(count)
        player.scheduleSegment(
            file, startingFrame: range.lowerBound, frameCount: count, at: nil,
            completionCallbackType: looping ? .dataConsumed : .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor in self?.segmentFinished(generation: gen, looping: looping) }
        }
    }

    private func segmentFinished(generation gen: Int, looping: Bool) {
        guard gen == generation, isPlaying else { return }
        if looping, let loop = loopFrames {
            // Keep two loop passes queued so repeats are gapless.
            schedule(loop, looping: true, generation: gen)
        } else if !looping {
            discardScheduledAudio()
            isPlaying = false
            stopTimer()
            anchorFrame = lengthFrames
            currentTime = duration
        }
    }

    private func discardScheduledAudio() {
        generation += 1
        player.stop()
        segments.removeAll()
        scheduledFrames = 0
    }

    private func currentFrame() -> AVAudioFramePosition {
        guard isPlaying,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime)
        else { return anchorFrame }
        let sample = playerTime.sampleTime
        guard let segment = segments.last(where: { sample >= $0.playerStart }) ?? segments.first else {
            return anchorFrame
        }
        let offset = max(0, min(sample - segment.playerStart, AVAudioFramePosition(segment.length)))
        return clampFrame(segment.fileStart + offset)
    }

    private func clampFrame(_ frame: AVAudioFramePosition) -> AVAudioFramePosition {
        max(0, min(frame, lengthFrames))
    }

    private func time(of frame: AVAudioFramePosition) -> TimeInterval {
        Double(frame) / sampleRate
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isPlaying else { return }
        currentTime = time(of: currentFrame())
    }

    /// Output device changes (headphones, AirPods, sample-rate switches) stop the engine; restart it in place.
    private func handleConfigurationChange() {
        let wasPlaying = isPlaying
        let frame = currentFrame()
        stop()
        anchorFrame = frame
        do {
            engine.prepare()
            try engine.start()
            if wasPlaying { scheduleAndPlay(from: frame) }
        } catch {
            errorMessage = "Audio output changed and couldn't restart: \(error.localizedDescription)"
        }
    }
}
