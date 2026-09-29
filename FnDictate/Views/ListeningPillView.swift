import AppKit
import SwiftUI

/// Wispr-style vertical listening rail: cancel · waveform · confirm, docked to the side.
struct ListeningPillView: View {
    @Bindable var model: AppModel

    private var isLive: Bool {
        model.phase == .listening || model.phase == .meetingRecording
    }

    var body: some View {
        VStack(spacing: 14) {
            Button {
                model.cancelListeningPill()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .help(cancelHelp)

            ZStack {
                WindowDragHandle(onClick: nil)
                SideWaveformView(
                    level: model.audioLevel,
                    isActive: isLive,
                    tint: indicatorColor
                )
                .frame(width: 22, height: 72)
                .allowsHitTesting(false)
            }
            .frame(width: 28, height: 72)
            .help("Listening — drag to move")

            Button {
                model.confirmListeningPill()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)
            .help(confirmHelp)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        // No compositingGroup shadow — that casts a square halo around the panel.
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .draggablePanel(
            onDragStart: { model.listeningPillOrigin() },
            onDragTo: { model.moveListeningPill(to: $0) }
        )
        .preferredColorScheme(.dark)
    }

    private var cancelHelp: String {
        switch model.phase {
        case .meetingRecording: return "Cancel meeting recording"
        default: return "Cancel dictation"
        }
    }

    private var expandedBody: some View {
        HStack(alignment: .center, spacing: 12) {
            // Grip + collapse: drag handle interprets short click as collapse.
            ZStack {
                WindowDragHandle(onClick: { model.collapseListeningPill() })
                if model.phase == .meetingRecording {
                    MeetingDualWaveformView(
                        youLevel: model.audioLevel,
                        othersLevel: model.remoteAudioLevel,
                        activeChannel: model.activeMeetingChannel,
                        remoteLabel: model.remoteSpeakerLabel
                    )
                    .frame(width: 72, height: 36)
                    .allowsHitTesting(false)
                } else {
                    VoiceWaveformView(
                        level: model.audioLevel,
                        isActive: isLive,
                        tint: indicatorColor
                    )
                    .frame(width: 44, height: 36)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: model.phase == .meetingRecording ? 72 : 44, height: 36)
            .help("Drag to move · click to collapse")

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    if model.phase == .meetingRecording {
                        MeetingChannelChips(
                            activeChannel: model.activeMeetingChannel,
                            remoteLabel: model.remoteSpeakerLabel,
                            systemAudioFailed: model.activeMeetingID.flatMap { id in
                                model.meetings.notes.first(where: { $0.id == id })?.systemAudioCaptureFailed
                            } ?? false
                        )
                    }
                    ScrollingTranscriptView(
                        text: displayText,
                        isLive: isLive
                    )
                    .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 48, alignment: .topLeading)
                }

                if model.phase == .listening, model.currentTone != .raw {
                    ToneChipButton(tone: model.currentTone) {
                        model.cycleTone()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: model.phase == .meetingRecording ? 420 : 380)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
    }

    private var displayText: String {
        if !model.partialText.isEmpty {
            return model.partialText
        }
        return model.statusMessage
    }

    private var confirmHelp: String {
        switch model.phase {
        case .meetingRecording: return "Stop and save meeting notes"
        default: return "Finish and paste"
        }
    }

    private var indicatorColor: Color {
        switch model.phase {
        case .listening, .meetingRecording: return .white
        case .processing, .meetingProcessing: return .orange
        case .idle: return .white.opacity(0.45)
        }
    }
}

private struct ToneChipButton: View {
    let tone: CleanupTone
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(tone.displayName)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help("Cleanup tone — click to cycle Raw / Light / Polished")
    }
}

struct ScrollingTranscriptView: View {
    let text: String
    let isLive: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                Text(text)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .id("transcriptTail")
            }
            .onChange(of: text) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("transcriptTail", anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo("transcriptTail", anchor: .bottom)
            }
        }
    }
}

struct VoiceWaveformView: View {
    let level: Float
    let isActive: Bool
    let tint: Color

    /// Avoid `TimelineView(.animation)` — on macOS 26+ its update path can crash in
    /// `swift_task_isMainExecutorImpl` during NSHostingView layout. Drive motion via
    /// Shape `animatableData` instead.
    @State private var phase: CGFloat = 0

    private let barCount = 5

    var body: some View {
        VoiceWaveformShape(
            phase: phase,
            level: CGFloat(level),
            isActive: isActive,
            barCount: barCount
        )
        .fill(tint.opacity(isActive ? 0.95 : 0.35))
        .onAppear { syncAnimation() }
        .onChange(of: isActive) { _, _ in syncAnimation() }
    }

    private func syncAnimation() {
        // `phase` is treated as elapsed seconds so bar math matches the old TimelineView.
        if isActive {
            phase = 0
            withAnimation(.linear(duration: 120).repeatForever(autoreverses: false)) {
                phase = 120
            }
        } else {
            withAnimation(.easeOut(duration: 0.15)) {
                phase = 0
            }
        }
    }
}

/// Vertical bars — heights encoded in a Path so SwiftUI can interpolate `phase` without TimelineView.
/// `level` is in `animatableData` so it keeps updating while `phase` is mid-animation (plain
/// Shape properties can otherwise freeze for the life of the transaction).
private struct VoiceWaveformShape: Shape {
    var phase: CGFloat
    var level: CGFloat
    var isActive: Bool
    var barCount: Int

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(phase, level) }
        set {
            phase = newValue.first
            level = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 3
        let barWidth: CGFloat = 4
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
        let originX = (rect.width - totalWidth) / 2
        let base: CGFloat = 6
        let maxExtra: CGFloat = min(28, max(0, rect.height - base))
        let speech = max(0.05, min(1, level))

        for index in 0..<barCount {
            let height: CGFloat
            if isActive {
                let barPhase = CGFloat(index) * 0.85
                let wobble = (sin(phase * (9.0 + CGFloat(index) * 1.7) + barPhase) + 1) / 2
                height = base + maxExtra * (0.25 * wobble + 0.75 * speech * (0.55 + 0.45 * wobble))
            } else {
                height = base
            }
            let x = originX + CGFloat(index) * (barWidth + spacing)
            let y = (rect.height - height) / 2
            path.addRoundedRect(
                in: CGRect(x: x, y: y, width: barWidth, height: height),
                cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)
            )
        }
        return path
    }
}

/// Horizontal bars stacked vertically — Wispr Flow side-rail waveform.
struct SideWaveformView: View {
    let level: Float
    let isActive: Bool
    let tint: Color

    /// Same TimelineView crash avoidance as `VoiceWaveformView`.
    @State private var phase: CGFloat = 0

    private let barCount = 11

    var body: some View {
        SideWaveformShape(
            phase: phase,
            level: CGFloat(level),
            isActive: isActive,
            barCount: barCount
        )
        .fill(tint.opacity(isActive ? 0.95 : 0.35))
        .onAppear { syncAnimation() }
        .onChange(of: isActive) { _, _ in syncAnimation() }
    }

    private func syncAnimation() {
        if isActive {
            phase = 0
            withAnimation(.linear(duration: 120).repeatForever(autoreverses: false)) {
                phase = 120
            }
        } else {
            withAnimation(.easeOut(duration: 0.15)) {
                phase = 0
            }
        }
    }
}

private struct SideWaveformShape: Shape {
    var phase: CGFloat
    var level: CGFloat
    var isActive: Bool
    var barCount: Int

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(phase, level) }
        set {
            phase = newValue.first
            level = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 2.5
        let barHeight: CGFloat = 2.5
        let totalHeight = CGFloat(barCount) * barHeight + CGFloat(barCount - 1) * spacing
        let originY = (rect.height - totalHeight) / 2
        let mid = CGFloat(barCount - 1) / 2
        let base: CGFloat = 4
        let maxExtra: CGFloat = min(16, max(0, rect.width - base))
        let speech = max(0.08, min(1, level))

        for index in 0..<barCount {
            let envelope = 1 - abs(CGFloat(index) - mid) / mid
            let width: CGFloat
            if isActive {
                let barPhase = CGFloat(index) * 0.55
                let wobble = (sin(phase * (10.0 + CGFloat(index) * 0.9) + barPhase) + 1) / 2
                let pulse = 0.3 * wobble + 0.7 * speech * (0.5 + 0.5 * wobble)
                width = base + maxExtra * envelope * (0.35 + 0.65 * pulse)
            } else {
                width = base + maxExtra * envelope * 0.45
            }
            let x = (rect.width - width) / 2
            let y = originY + CGFloat(index) * (barHeight + spacing)
            path.addRoundedRect(
                in: CGRect(x: x, y: y, width: width, height: barHeight),
                cornerSize: CGSize(width: barHeight / 2, height: barHeight / 2)
            )
        }
        return path
    }
}

/// Compact You | Others meters for meeting capture.
private struct MeetingDualWaveformView: View {
    let youLevel: Float
    let othersLevel: Float
    let activeChannel: AppModel.MeetingChannel?
    let remoteLabel: String

    var body: some View {
        HStack(spacing: 6) {
            VoiceWaveformView(
                level: youLevel,
                isActive: true,
                tint: activeChannel == .you ? Color.white : Color.white.opacity(0.45)
            )
            .frame(width: 28)
            VoiceWaveformView(
                level: othersLevel,
                isActive: true,
                tint: activeChannel == .others ? Color.cyan : Color.white.opacity(0.35)
            )
            .frame(width: 28)
        }
        .help("You · \(remoteLabel)")
    }
}

private struct MeetingChannelChips: View {
    let activeChannel: AppModel.MeetingChannel?
    let remoteLabel: String
    let systemAudioFailed: Bool

    var body: some View {
        HStack(spacing: 6) {
            chip("You", hot: activeChannel == .you, tint: .white)
            chip(remoteLabel, hot: activeChannel == .others, tint: .cyan)
            if systemAudioFailed {
                Text("Mic only")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.orange.opacity(0.95))
            }
        }
    }

    private func chip(_ title: String, hot: Bool, tint: Color) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(hot ? tint : .white.opacity(0.45))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(hot ? 0.18 : 0.08))
            )
    }
}

// MARK: - Panel dragging

extension View {
    /// SwiftUI drag → AppKit window move. Works alongside buttons via simultaneousGesture.
    func draggablePanel(
        onDragStart: @escaping () -> CGPoint,
        onDragTo: @escaping (CGPoint) -> Void
    ) -> some View {
        modifier(AbsolutePanelDragModifier(onDragStart: onDragStart, onDragTo: onDragTo))
    }
}

private struct AbsolutePanelDragModifier: ViewModifier {
    let onDragStart: () -> CGPoint
    let onDragTo: (CGPoint) -> Void

    @State private var startOrigin: CGPoint?
    @State private var dragging = false

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .global)
                .onChanged { value in
                    if !dragging {
                        dragging = true
                        startOrigin = onDragStart()
                    }
                    guard let startOrigin else { return }
                    // SwiftUI +y is down; AppKit window +y is up.
                    onDragTo(
                        CGPoint(
                            x: startOrigin.x + value.translation.width,
                            y: startOrigin.y - value.translation.height
                        )
                    )
                }
                .onEnded { _ in
                    dragging = false
                    startOrigin = nil
                }
        )
    }
}

/// AppKit drag handle — click (no drag) fires `onClick`; drag moves the window.
/// Optional `onHover` uses a tracking area so expand works even when the panel isn't key.
struct WindowDragHandle: NSViewRepresentable {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?

    func makeNSView(context: Context) -> WindowDragNSView {
        let view = WindowDragNSView()
        view.onClick = onClick
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: WindowDragNSView, context: Context) {
        nsView.onClick = onClick
        nsView.onHover = onHover
        nsView.updateTrackingAreas()
    }
}

final class WindowDragNSView: NSView {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private let clickSlop: CGFloat = 5

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        guard onHover != nil else { return }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Always claim hits inside our bounds so we sit above SwiftUI chrome.
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let downScreen = NSEvent.mouseLocation
        let originOnDown = window.frame.origin
        var dragged = false

        while true {
            guard let tracked = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else { break }

            if tracked.type == .leftMouseUp {
                if !dragged {
                    onClick?()
                }
                break
            }

            let now = NSEvent.mouseLocation
            let dx = now.x - downScreen.x
            let dy = now.y - downScreen.y
            if hypot(dx, dy) >= clickSlop {
                dragged = true
            }
            if dragged {
                window.setFrameOrigin(NSPoint(x: originOnDown.x + dx, y: originOnDown.y + dy))
            }
        }
    }
}
