import SwiftUI

struct ListeningPillView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VoiceWaveformView(
                level: model.audioLevel,
                isActive: model.phase == .listening || model.phase == .meetingRecording,
                tint: indicatorColor
            )
            .frame(width: 44, height: 36)

            HStack(alignment: .top, spacing: 8) {
                ScrollingTranscriptView(
                    text: displayText,
                    isLive: model.phase == .listening || model.phase == .meetingRecording
                )
                .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 48, alignment: .topLeading)

                if model.phase == .listening {
                    ToneChipButton(tone: model.currentTone) {
                        model.cycleTone()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: 380)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .preferredColorScheme(.dark)
    }

    private var displayText: String {
        if !model.partialText.isEmpty {
            return model.partialText
        }
        return model.statusMessage
    }

    private var indicatorColor: Color {
        switch model.phase {
        case .listening, .meetingRecording: return .white
        case .processing, .meetingProcessing: return .orange
        case .idle: return .green
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

/// Multi-line transcript that always keeps the latest words visible.
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

/// Animated bars driven by live microphone level.
struct VoiceWaveformView: View {
    let level: Float
    let isActive: Bool
    let tint: Color

    private let barCount = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(tint.opacity(isActive ? 0.95 : 0.35))
                        .frame(width: 4, height: barHeight(index: index, time: t))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private func barHeight(index: Int, time: TimeInterval) -> CGFloat {
        let base: CGFloat = 6
        let maxExtra: CGFloat = 28
        guard isActive else { return base }

        // Stagger each bar so the waveform feels alive, not a flat level meter.
        let phase = Double(index) * 0.85
        let wobble = (sin(time * (9.0 + Double(index) * 1.7) + phase) + 1) / 2
        let speech = CGFloat(max(0.05, min(1, level)))
        let height = base + maxExtra * (0.25 * CGFloat(wobble) + 0.75 * speech * CGFloat(0.55 + 0.45 * wobble))
        return height
    }
}
