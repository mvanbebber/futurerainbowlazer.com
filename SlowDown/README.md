# SlowDown: music transcription practice for Mac and iPhone

SlowDown copies the core of [Transcribe!](https://www.seventhstring.com/xscribe/overview.html): load a song,
slow it down without changing the pitch, loop the hard bit, mark the bars, and work out the notes.
It's a native SwiftUI app for macOS 14+ and iOS 17+ that shares one codebase.

## Features

| Transcribe! feature | SlowDown |
| --- | --- |
| Slow down without changing pitch | 25 % – 200 % speed, with ±5 % steps and presets (50, 60, 70, 75, 80, 90, 100 %) |
| Transpose / fine tune | ±24 semitones, ±50 cents fine tuning (for recordings that aren't at A440), speed unchanged |
| Waveform | Zoomable waveform with time ruler, whole-song overview, follow-playhead, pinch to zoom |
| Loops | Drag across the waveform or press **A** / **B**. Gapless repeats, nudge loop points by ±0.05 s / ±0.5 s, saved named loops |
| Markers | Section, measure and beat markers. Measures are numbered automatically. "Loop from here" loops a whole section or bar |
| EQ | 5-band EQ with presets (Bass focus, Vocal focus, Guitar/keys, Drums, Treble focus…) |
| Karaoke / channels | Stereo, mono, left only, right only, karaoke (center-channel cancel to drop out vocals) |
| Spectrum / note guessing | Piano-keyboard spectrum of the notes sounding at the playhead, adjusted for transposition |
| Remembers everything | Speed, pitch, EQ, channel mode, loops, markers and position are saved per song |

### Supported files

WAV, AIFF, CAF, FLAC, MP3, M4A/AAC/ALAC, Apple **Voice Memos** (`.m4a` and `.qta`), and video and other
containers (MP4, MOV, M4V, 3GP). Audio files Core Audio can read are copied as-is. For everything else the
audio track is extracted and stored as AAC.

You can add files by:
- **+ › Import Audio or Video…** (Files app / Finder, iCloud Drive, etc.)
- dragging files onto the library (Mac, iPad)
- **Open in / Share › SlowDown** from other apps, such as Voice Memos › Share, Files or Mail

### Capturing YouTube, Spotify and other apps

**Mac:** **+ › Capture Audio From an App…** lists the running apps. Pick a browser for YouTube, or Spotify,
Music and so on, then press **Record** and play the song. SlowDown uses ScreenCaptureKit to record only that
app's audio, digitally, with no microphone and no other apps' sounds. The first time, macOS asks for
*Screen & System Audio Recording* permission (System Settings › Privacy & Security). After granting it,
reopen SlowDown.

**iPhone / iPad:** iOS doesn't let one app record another directly, so SlowDown includes a ReplayKit
broadcast extension, *SlowDown Capture*. Open **+ › Capture Audio From an App…**, tap the record button,
choose *SlowDown Capture*, then **Start Broadcast**. Switch to YouTube or Spotify and play, then stop from
the red status-bar pill or the same button. The extension saves only the app audio (no video, no
microphone) into the shared App Group, and the recording appears in the library when you return.
Apps that mark their audio as protected, such as Apple Music, come out silent. For those, use
**Record With Microphone…** or capture on the Mac.

> Capture is meant for personal practice. Respect the terms of the services you record from and the
> rights of the artists.

### Keyboard shortcuts (Mac, and iPad with a keyboard)

| Key | Action |
| --- | --- |
| Space | Play / pause |
| ← / → | Back / forward 5 s |
| ⌥← / ⌥→ | Previous / next marker |
| Return | Back to start of loop (or song) |
| A / B | Set loop start / end at the playhead |
| L | Loop on/off |
| [ / ] | Speed −5 % / +5 % |
| S / M / N | Add section / measure / beat marker |

## Building

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
cd SlowDown
xcodegen generate
open SlowDown.xcodeproj
```

Then in Xcode:

1. Select your team under **Signing & Capabilities** for all three targets (`SlowDown-macOS`, `SlowDown-iOS`,
   `SlowDownBroadcast`). You can also set `DEVELOPMENT_TEAM` in `project.yml`.
2. If `com.futurerainbowlazer.slowdown` is unavailable to your team, change the bundle IDs in `project.yml`.
   The broadcast extension must stay `<app id>.Broadcast`. Also change the App Group
   (`group.com.futurerainbowlazer.slowdown`) in `project.yml` and in `Shared/Support/StorageLocation.swift`.
3. Run **SlowDown-macOS** on "My Mac", or **SlowDown-iOS** on an iPhone. The broadcast extension only works on a
   real device, not in the Simulator.

CI (`.github/workflows/slowdown-build.yml`) builds both apps on every push without code signing.

## How it works

```
Shared/
  Audio/PlaybackEngine.swift    AVAudioPlayerNode → AVAudioUnitTimePitch → AVAudioUnitEQ → output.
                                Segment scheduling gives exact positions and gapless loops at any speed.
  Audio/AudioImporter.swift     Copies readable audio; extracts audio from video/other containers via AVAssetReader.
  Audio/ChannelProcessor.swift  Renders mono / left / right / karaoke versions once and caches them.
  Audio/Waveform.swift          200 peaks per second, drawn at any zoom.
  Audio/SpectrumAnalyzer.swift  32k-point FFT → energy per piano note.
  Capture/CaptureFileWriter.swift  Sample buffers → AAC .m4a, used by both capture paths and the importer.
  Model/                        Recording, markers, loops, settings; JSON-backed Library.
  Player/PlayerController.swift Binds a recording's saved settings to the engine.
  Views/                        SwiftUI, shared by both platforms.
macOS/SystemAudioCapture.swift  ScreenCaptureKit per-app audio capture.
iOS/PhoneCaptureView.swift      RPSystemBroadcastPickerView for the broadcast extension.
BroadcastExtension/             ReplayKit sample handler that writes app audio to the App Group.
```
