import SwiftUI

struct ListeningPillView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 10, height: 10)
                .shadow(color: indicatorColor.opacity(0.8), radius: model.phase == .listening || model.phase == .meetingRecording ? 6 : 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 320)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
    }

    private var title: String {
        switch model.phase {
        case .listening: return "Listening"
        case .processing: return "Processing"
        case .meetingRecording: return "Meeting"
        case .meetingProcessing: return "Summarizing"
        case .idle: return "Fn Dictate"
        }
    }

    private var subtitle: String {
        if !model.partialText.isEmpty {
            return model.partialText
        }
        return model.statusMessage
    }

    private var indicatorColor: Color {
        switch model.phase {
        case .listening, .meetingRecording: return .red
        case .processing, .meetingProcessing: return .orange
        case .idle: return .green
        }
    }
}
