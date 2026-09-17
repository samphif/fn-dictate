import AppKit
import SwiftUI

/// Wispr-style floating rail: collapsed edge handle by default, expands for meeting actions.
struct MeetingPromptView: View {
    @Bindable var model: AppModel

    private var isExpanded: Bool {
        (model.showMeetingPrompt && !model.meetingPromptMinimized) || model.flowSidebarExpanded
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedBody
            } else {
                collapsedBody
            }
        }
        // Leave room so SwiftUI shadows aren't clipped by the panel bounds.
        .padding(14)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isExpanded)
        .draggablePanel(
            onDragStart: { model.flowSidebarOrigin() },
            onDragTo: { model.moveFlowSidebar(to: $0) }
        )
        .preferredColorScheme(.dark)
    }

    private var collapsedBody: some View {
        ZStack {
            WindowDragHandle(onClick: { model.toggleFlowSidebar() })

            VStack(spacing: 10) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 16, height: 3)

                Image(systemName: model.showMeetingPrompt ? "video.fill" : "waveform.circle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(model.showMeetingPrompt ? Color.accentColor : .white.opacity(0.92))
                    .symbolRenderingMode(.hierarchical)

                if model.showMeetingPrompt {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
            }
            .allowsHitTesting(false)
        }
        .frame(width: 44, height: 112)
        .background {
            ZStack {
                Capsule(style: .continuous)
                    .fill(.regularMaterial)
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.28))
            }
        }
        .clipShape(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        )
        .compositingGroup()
        .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
        .help(model.showMeetingPrompt
              ? "Meeting detected — drag to move, click to expand"
              : "Fn Dictate — drag to move, click to expand")
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    WindowDragHandle(onClick: nil)
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 28, height: 3)
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 18)
                .help("Drag to move")

                Button {
                    model.collapseFlowSidebar()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Collapse")
            }

            if model.showMeetingPrompt {
                meetingPromptContent
            } else {
                idleExpandedContent
            }
        }
        .padding(14)
        .frame(width: 280)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.28))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        )
        .compositingGroup()
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
    }

    private var meetingPromptContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.2))
                        .frame(width: 36, height: 36)
                    Image(systemName: "video.fill")
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Meeting detected")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(model.detectedMeeting?.appName ?? "Call")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if let detail = model.detectedMeeting?.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button {
                    model.dismissMeetingPrompt()
                } label: {
                    Text("Not now")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    model.acceptDetectedMeeting()
                } label: {
                    Label("Start notes", systemImage: "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private var idleExpandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fn Dictate")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text("Hold Fn to dictate. Meeting notes appear here when a call starts.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                model.collapseFlowSidebar()
            } label: {
                Text("Collapse")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }
}

/// Hosting controller that keeps its layer fully clear so rounded SwiftUI chrome
/// isn't boxed by the default opaque (often black) AppKit view background.
final class ClearHostingController<Content: View>: NSHostingController<Content> {
    override func viewDidLoad() {
        super.viewDidLoad()
        clearBackground()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        clearBackground()
    }

    private func clearBackground() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.isOpaque = false
    }
}
