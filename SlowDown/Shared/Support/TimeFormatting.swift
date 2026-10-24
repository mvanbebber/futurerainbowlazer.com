import Foundation

extension TimeInterval {
    /// "1:23.45" — minutes, seconds and hundredths, for the playhead and loop points.
    var preciseClock: String {
        let total = max(0, self)
        let minutes = Int(total) / 60
        let seconds = total - Double(minutes * 60)
        return String(format: "%d:%05.2f", minutes, seconds)
    }

    /// "1:23" — for durations in lists.
    var shortClock: String {
        let total = Int(max(0, self).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
