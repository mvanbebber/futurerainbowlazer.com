import Foundation

/// One song or recording in the library, together with everything the user has set up for practising it.
struct Recording: Identifiable, Codable, Hashable {
    enum Source: String, Codable {
        case imported
        case systemCapture
        case microphone

        var symbolName: String {
            switch self {
            case .imported: "doc.badge.plus"
            case .systemCapture: "record.circle"
            case .microphone: "mic"
            }
        }
    }

    var id = UUID()
    var title: String
    var fileName: String
    var dateAdded = Date()
    var duration: TimeInterval
    var source: Source = .imported
    var markers: [Marker] = []
    var loops: [SavedLoop] = []
    var settings = PracticeSettings()

    /// Display text for a marker. Measures are numbered automatically ("Bar 1", "Bar 2", …) like Transcribe!.
    func label(for marker: Marker) -> String {
        if !marker.label.isEmpty { return marker.label }
        switch marker.kind {
        case .section:
            let index = markers.filter { $0.kind == .section && $0.time <= marker.time }.count
            return "Section \(index)"
        case .measure:
            let index = markers.filter { $0.kind == .measure && $0.time <= marker.time }.count
            return "\(index)"
        case .beat:
            return ""
        }
    }
}

struct Marker: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case section
        case measure
        case beat

        var id: String { rawValue }

        var title: String {
            switch self {
            case .section: "Section"
            case .measure: "Measure"
            case .beat: "Beat"
            }
        }

        var symbolName: String {
            switch self {
            case .section: "flag.fill"
            case .measure: "line.diagonal"
            case .beat: "circle.fill"
            }
        }
    }

    var id = UUID()
    var time: TimeInterval
    var kind: Kind
    var label: String = ""
}

struct SavedLoop: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var start: TimeInterval
    var end: TimeInterval
}

enum ChannelMode: String, Codable, CaseIterable, Identifiable {
    case stereo
    case mono
    case left
    case right
    case karaoke

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stereo: "Stereo"
        case .mono: "Mono"
        case .left: "Left only"
        case .right: "Right only"
        case .karaoke: "Karaoke (cancel center)"
        }
    }
}

struct PracticeSettings: Codable, Hashable {
    var speed: Double = 1
    var semitones: Int = 0
    var cents: Double = 0
    var volume: Double = 1
    var channelMode: ChannelMode = .stereo
    var eqGains: [Double] = Array(repeating: 0, count: EQBand.all.count)
    var lastPosition: TimeInterval = 0
    var loopStart: TimeInterval?
    var loopEnd: TimeInterval?
    var loopEnabled = false

    var pitchCents: Double { Double(semitones) * 100 + cents }
}

struct EQBand {
    enum Shape { case lowShelf, peak, highShelf }

    let frequency: Float
    let shape: Shape
    let label: String

    static let all: [EQBand] = [
        EQBand(frequency: 80, shape: .lowShelf, label: "Bass"),
        EQBand(frequency: 300, shape: .peak, label: "Low mid"),
        EQBand(frequency: 1_000, shape: .peak, label: "Mid"),
        EQBand(frequency: 3_000, shape: .peak, label: "High mid"),
        EQBand(frequency: 8_000, shape: .highShelf, label: "Treble"),
    ]

    static let presets: [(name: String, gains: [Double])] = [
        ("Flat", [0, 0, 0, 0, 0]),
        ("Bass focus", [9, 3, -15, -21, -24]),
        ("Bass boost", [8, 3, 0, 0, 0]),
        ("Vocal focus", [-15, -4, 6, 5, -6]),
        ("Guitar / keys", [-9, 2, 6, 3, -4]),
        ("Drums & cymbals", [3, -6, -6, 3, 9]),
        ("Treble focus", [-24, -18, -3, 6, 8]),
    ]
}
