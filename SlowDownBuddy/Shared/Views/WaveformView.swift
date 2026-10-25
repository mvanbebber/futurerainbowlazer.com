import SwiftUI

/// Zoomable waveform with playhead, markers and the loop region.
///
/// Tap to move the playhead, drag across to make a loop, pinch (or use the buttons) to zoom.
/// The strip underneath shows the whole song; drag it to scroll.
struct WaveformView: View {
    let controller: PlayerController

    @State private var visibleDuration: TimeInterval = 20
    @State private var viewStart: TimeInterval = 0
    @State private var selection: ClosedRange<TimeInterval>?
    @State private var zoomAtGestureStart: TimeInterval?
    @State private var followPlayhead = true

    private var duration: TimeInterval { max(controller.engine.duration, 0.01) }
    private var span: TimeInterval { min(max(visibleDuration, 0.5), duration) }

    var body: some View {
        let snapshot = WaveformSnapshot(
            peaks: controller.waveform,
            viewStart: viewStart,
            span: span,
            playhead: controller.engine.currentTime,
            loop: loopRange,
            loopEnabled: controller.loopActive,
            selection: selection,
            markers: controller.recording.markers.map { (time: $0.time, kind: $0.kind, label: controller.label(for: $0)) })

        VStack(spacing: 6) {
            GeometryReader { geo in
                Canvas { context, size in
                    snapshot.draw(in: context, size: size)
                }
                .contentShape(Rectangle())
                .gesture(selectGesture(width: geo.size.width))
                .simultaneousGesture(zoomGesture)
                .overlay {
                    if controller.waveform == nil {
                        ProgressView().tint(.white)
                    }
                }
            }
            .frame(height: 170)
            .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if span < duration {
                overview
            }

            HStack(spacing: 14) {
                Button("Zoom Out", systemImage: "minus.magnifyingglass") { zoom(by: 1.6) }
                Button("Zoom In", systemImage: "plus.magnifyingglass") { zoom(by: 1 / 1.6) }
                Button("Whole Song", systemImage: "arrow.left.and.right") { setSpan(duration) }
                Spacer()
                Toggle(isOn: $followPlayhead) {
                    Label("Follow", systemImage: "scope")
                }
                .toggleStyle(.button)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.title3)
        }
        .onChange(of: controller.engine.currentTime) { _, time in
            guard followPlayhead, controller.engine.isPlaying, span < duration else { return }
            if time < viewStart || time > viewStart + span * 0.92 {
                viewStart = clampedStart(time - span * 0.08)
            }
        }
        .onChange(of: controller.engine.duration, initial: true) { _, newDuration in
            visibleDuration = min(20, max(newDuration, 0.5))
            viewStart = clampedStart(controller.engine.currentTime - visibleDuration * 0.08)
        }
    }

    private var loopRange: ClosedRange<TimeInterval>? {
        guard let a = controller.loopStart, let b = controller.loopEnd, b > a else { return nil }
        return a...b
    }

    private var overview: some View {
        let snapshot = WaveformSnapshot(
            peaks: controller.waveform, viewStart: 0, span: duration,
            playhead: controller.engine.currentTime, loop: loopRange, loopEnabled: controller.loopActive,
            selection: nil, markers: [], window: viewStart...(viewStart + span))
        return GeometryReader { geo in
            Canvas { context, size in snapshot.draw(in: context, size: size) }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        let center = Double(value.location.x / max(geo.size.width, 1)) * duration
                        viewStart = clampedStart(center - span / 2)
                        followPlayhead = false
                    })
        }
        .frame(height: 36)
        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func time(atX x: CGFloat, width: CGFloat) -> TimeInterval {
        let fraction = Double(min(max(x / max(width, 1), 0), 1))
        return viewStart + fraction * span
    }

    private func selectGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard abs(value.translation.width) > 6 else { return }
                let a = time(atX: value.startLocation.x, width: width)
                let b = time(atX: value.location.x, width: width)
                selection = min(a, b)...max(a, b)
            }
            .onEnded { value in
                if abs(value.translation.width) <= 6 {
                    controller.seek(to: time(atX: value.location.x, width: width))
                } else if let selection {
                    controller.setLoop(start: selection.lowerBound, end: selection.upperBound)
                }
                selection = nil
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if zoomAtGestureStart == nil { zoomAtGestureStart = span }
                setSpan((zoomAtGestureStart ?? span) / max(value.magnification, 0.05))
            }
            .onEnded { _ in zoomAtGestureStart = nil }
    }

    private func zoom(by factor: Double) {
        setSpan(span * factor)
    }

    /// Changes the zoom while keeping the playhead (if visible) or the center in place.
    private func setSpan(_ newSpan: TimeInterval) {
        let clamped = min(max(newSpan, 0.5), duration)
        let playhead = controller.engine.currentTime
        let anchor = (viewStart...(viewStart + span)).contains(playhead) ? playhead : viewStart + span / 2
        let anchorFraction = span > 0 ? (anchor - viewStart) / span : 0.5
        visibleDuration = clamped
        viewStart = clampedStart(anchor - anchorFraction * clamped)
    }

    private func clampedStart(_ start: TimeInterval) -> TimeInterval {
        min(max(start, 0), max(duration - span, 0))
    }
}

/// Everything the waveform needs to draw one frame, captured in `body` so SwiftUI tracks the dependencies.
private struct WaveformSnapshot {
    let peaks: WaveformData?
    let viewStart: TimeInterval
    let span: TimeInterval
    let playhead: TimeInterval
    let loop: ClosedRange<TimeInterval>?
    let loopEnabled: Bool
    let selection: ClosedRange<TimeInterval>?
    let markers: [(time: TimeInterval, kind: Marker.Kind, label: String)]
    var window: ClosedRange<TimeInterval>? = nil

    func draw(in context: GraphicsContext, size: CGSize) {
        guard span > 0, size.width > 0 else { return }
        let width = size.width
        func x(_ t: TimeInterval) -> CGFloat { CGFloat((t - viewStart) / span) * width }
        let compact = size.height < 60

        if let loop {
            let rect = CGRect(x: x(loop.lowerBound), y: 0, width: x(loop.upperBound) - x(loop.lowerBound), height: size.height)
            context.fill(Path(rect), with: .color(Color.yellow.opacity(loopEnabled ? 0.28 : 0.12)))
            if !compact {
                for edge in [loop.lowerBound, loop.upperBound] {
                    context.fill(Path(CGRect(x: x(edge) - 1, y: 0, width: 2, height: size.height)),
                                 with: .color(Color.yellow.opacity(loopEnabled ? 0.9 : 0.4)))
                }
            }
        }
        if let selection {
            let rect = CGRect(x: x(selection.lowerBound), y: 0, width: x(selection.upperBound) - x(selection.lowerBound), height: size.height)
            context.fill(Path(rect), with: .color(Color.white.opacity(0.2)))
        }
        if let window {
            let rect = CGRect(x: x(window.lowerBound), y: 0, width: max(2, x(window.upperBound) - x(window.lowerBound)), height: size.height)
            context.fill(Path(rect), with: .color(Color.white.opacity(0.18)))
            context.stroke(Path(rect), with: .color(.white.opacity(0.6)), lineWidth: 1)
        }

        if let peaks {
            let rulerHeight: CGFloat = compact ? 0 : 16
            let mid = (size.height - rulerHeight) / 2
            var path = Path()
            let secondsPerPoint = span / Double(width)
            var column: CGFloat = 0
            while column < width {
                let t = viewStart + Double(column) * secondsPerPoint
                let level = CGFloat(peaks.peak(from: t, to: t + secondsPerPoint))
                let height = max(level * mid * 0.95, 0.5)
                path.addRect(CGRect(x: column, y: mid - height, width: 1, height: height * 2))
                column += 1
            }
            context.fill(path, with: .color(Color(red: 0.35, green: 0.85, blue: 1.0)))
            if !compact { drawRuler(in: context, size: size, x: x) }
        }

        for marker in markers where marker.time >= viewStart && marker.time <= viewStart + span {
            let mx = x(marker.time)
            let color: Color
            let lineWidth: CGFloat
            switch marker.kind {
            case .section: color = .orange; lineWidth = 2
            case .measure: color = .white.opacity(0.75); lineWidth = 1
            case .beat: color = .white.opacity(0.35); lineWidth = 1
            }
            context.fill(Path(CGRect(x: mx - lineWidth / 2, y: 0, width: lineWidth, height: size.height)), with: .color(color))
            if !marker.label.isEmpty {
                let text = Text(marker.label)
                    .font(marker.kind == .section ? Font.caption.bold() : Font.caption2)
                    .foregroundStyle(color)
                context.draw(text, at: CGPoint(x: mx + 3, y: marker.kind == .section ? 3 : 18), anchor: .topLeading)
            }
        }

        let px = x(playhead)
        if px >= -2 && px <= width + 2 {
            context.fill(Path(CGRect(x: px - 1, y: 0, width: 2, height: size.height)), with: .color(.red))
        }
    }

    private func drawRuler(in context: GraphicsContext, size: CGSize, x: (TimeInterval) -> CGFloat) {
        let steps: [TimeInterval] = [0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
        let targetTicks = max(Double(size.width) / 90, 2)
        let step = steps.first { span / $0 <= targetTicks } ?? 600
        var t = (viewStart / step).rounded(.up) * step
        while t <= viewStart + span {
            let tx = x(t)
            context.fill(Path(CGRect(x: tx, y: size.height - 16, width: 1, height: 5)), with: .color(.white.opacity(0.5)))
            let label = step < 1 ? String(format: "%.2f", t.truncatingRemainder(dividingBy: 60)) : t.shortClock
            context.draw(Text(label).font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.6)),
                         at: CGPoint(x: tx + 2, y: size.height - 11), anchor: .topLeading)
            t += step
        }
    }
}
