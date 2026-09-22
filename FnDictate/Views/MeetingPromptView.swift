import AppKit
import SwiftUI

/// Wispr-style floating rail: tiny edge handle by default, expands into a Dictate cluster.
struct MeetingPromptView: View {
    @Bindable var model: AppModel
    @State private var hoverCollapseTask: Task<Void, Never>?
    @State private var hoverExpandTask: Task<Void, Never>?

    private var isExpanded: Bool {
        (model.showMeetingPrompt && !model.meetingPromptMinimized) || model.flowSidebarExpanded
    }

    private var showMeetingSheet: Bool {
        model.showMeetingPrompt && !model.meetingPromptMinimized
    }

    private var detectedSourceLabel: String {
        AppDisplayName.meetingSource(
            appName: model.detectedMeeting?.appName,
            bundleID: model.detectedMeeting?.bundleID,
            detail: model.detectedMeeting?.detail
        ) ?? model.detectedMeeting?.appName ?? "Call"
    }

    private var railAnimation: Animation {
        .easeInOut(duration: 0.28)
    }

    var body: some View {
        Group {
            if showMeetingSheet {
                meetingExpandedBody
            } else {
                idleRailBody
            }
        }
        // Keep chrome glued to the screen edge if the panel is slightly oversized.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .animation(railAnimation, value: isExpanded)
        .animation(railAnimation, value: showMeetingSheet)
        .draggablePanel(
            onDragStart: { model.flowSidebarOrigin() },
            onDragTo: { model.moveFlowSidebar(to: $0) }
        )
        .preferredColorScheme(.dark)
        .onDisappear {
            hoverCollapseTask?.cancel()
            hoverExpandTask?.cancel()
            hoverCollapseTask = nil
            hoverExpandTask = nil
        }
    }

    // MARK: - Hover

    private func handleHover(_ hovering: Bool) {
        hoverCollapseTask?.cancel()
        hoverExpandTask?.cancel()
        hoverCollapseTask = nil
        hoverExpandTask = nil

        if hovering {
            // Brief dwell so the cursor crossing the edge doesn't flicker open.
            hoverExpandTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 70_000_000)
                guard !Task.isCancelled else { return }
                expandFromHover()
            }
        } else {
            hoverCollapseTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 420_000_000)
                guard !Task.isCancelled else { return }
                model.collapseFlowSidebar()
            }
        }
    }

    private func expandFromHover() {
        if model.showMeetingPrompt, model.meetingPromptMinimized {
            model.toggleFlowSidebar()
        } else if !model.showMeetingPrompt, !model.flowSidebarExpanded {
            model.toggleFlowSidebar()
        }
    }

    // MARK: - Idle rail (morphing collapse ↔ expand)

    /// One continuous layout: cluster width/opacity morphs; handle stays docked.
    private var idleRailBody: some View {
        HStack(alignment: .center, spacing: isExpanded ? 8 : 0) {
            flowClusterControls
                .opacity(isExpanded ? 1 : 0)
                .scaleEffect(isExpanded ? 1 : 0.92, anchor: .trailing)
                .frame(width: isExpanded ? nil : 0, alignment: .trailing)
                .clipped()
                .allowsHitTesting(isExpanded)

            edgeHandle(
                onClick: {
                    if isExpanded {
                        model.collapseFlowSidebar()
                    } else {
                        model.toggleFlowSidebar()
                    }
                },
                help: isExpanded
                    ? "Drag to move · click to collapse"
                    : "Fn Dictate — hover or click to expand"
            )
        }
        // Shadow room inward only; trailing stays flush. No group shadow (avoids square halo).
        .padding(.leading, isExpanded ? 12 : 6)
        .padding(.vertical, isExpanded ? 12 : 6)
        .padding(.trailing, 1)
        // Capture hits across spacing without an opaque rectangular fill that shadows.
        .contentShape(Rectangle())
        .background(Color.black.opacity(0.001))
        .onHover(perform: handleHover)
    }

    private var flowClusterControls: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                model.startHandsFreeDictationFromUI()
            } label: {
                HStack(spacing: 0) {
                    Text("Dictate ")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                    Text("fn")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.92))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .help("Start hands-free dictation (same as double-tap Fn)")

            VStack(spacing: 8) {
                Button {
                    model.startHandsFreeDictationFromUI()
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .frame(width: 36, height: 52)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.55))
                        }
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .help("Start hands-free dictation")

                Button {
                    model.toggleMeeting()
                    model.collapseFlowSidebar()
                } label: {
                    Image(systemName: "record.circle")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .help("Start meeting notes")
            }
        }
    }

    private func edgeHandle(onClick: @escaping () -> Void, help: String) -> some View {
        ZStack {
            WindowDragHandle(
                onClick: onClick,
                onHover: handleHover
            )
            Color.clear.allowsHitTesting(false)
        }
        .frame(width: 8, height: 36)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.88))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8)
        )
        .help(help)
    }

    // MARK: - Meeting sheet

    private var meetingExpandedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    WindowDragHandle(onClick: nil)
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.35))
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

            meetingPromptContent
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
        .padding(12)
        .onHover(perform: handleHover)
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
                    Text(detectedSourceLabel)
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
}

/// Hosting controller that keeps its layer fully clear so rounded SwiftUI chrome
/// isn't boxed by the default opaque (often black) AppKit view background.
///
/// Avoid `viewDidLayout` — on recent macOS/Swift runtimes the MainActor executor
/// check at the top of that override can crash during AppKit display-cycle layout.
final class ClearHostingController<Content: View>: NSHostingController<Content> {
    override func viewDidLoad() {
        super.viewDidLoad()
        clearBackground()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        clearBackground()
    }

    private func clearBackground() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.isOpaque = false
    }
}
