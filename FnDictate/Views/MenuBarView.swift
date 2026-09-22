import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var model: AppModel
    var appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    private var isBusyDictating: Bool {
        model.phase == .listening || model.phase == .processing || model.phase == .meetingProcessing
    }

    private var isRecordingMeeting: Bool {
        model.phase == .meetingRecording
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().padding(.vertical, 8)

            VStack(spacing: 2) {
                menuButton(
                    title: isRecordingMeeting ? "Stop meeting" : "Start meeting",
                    systemImage: isRecordingMeeting ? "stop.circle.fill" : "record.circle",
                    shortcut: "⌥M",
                    tint: isRecordingMeeting ? .red : nil
                ) {
                    model.toggleMeeting()
                }
                .disabled(isBusyDictating)

                systemAudioRow

                Toggle(isOn: $model.autoStopRecordingWhenMeetingEnds) {
                    Label {
                        Text("Auto-stop when call ends")
                            .font(.body)
                    } icon: {
                        Image(systemName: "stop.circle")
                            .frame(width: 18, alignment: .center)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .help("When a detected Zoom, Teams, Meet, or similar call ends, stop recording and save notes.")

                Toggle(isOn: $model.learnFromInAppCorrections) {
                    Label {
                        Text("Learn from edits")
                            .font(.body)
                    } icon: {
                        Image(systemName: "text.badge.checkmark")
                            .frame(width: 18, alignment: .center)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .help("After paste, learn spelling fixes you make in the app (uses Accessibility).")

                Picker(selection: $model.asrEngineMode) {
                    ForEach(ASREngineMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                } label: {
                    Label {
                        Text("Speech engine")
                            .font(.body)
                    } icon: {
                        Image(systemName: "waveform")
                            .frame(width: 18, alignment: .center)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .help(model.asrEngineMode.help)

                menuButton(title: "Library", systemImage: "books.vertical") {
                    appDelegate.presentLibrary()
                }

                menuButton(title: "Permissions", systemImage: "lock.shield") {
                    model.requestSetup()
                }
            }

            if let last = model.history.entries.first {
                Divider().padding(.vertical, 8)

                VStack(spacing: 2) {
                    menuButton(title: "Copy last transcript", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(last.text, forType: .string)
                    }

                    menuButton(title: "Paste last transcript", systemImage: "clipboard") {
                        TextPaster.paste(last.text)
                    }
                }
            }

            if let error = model.lastError {
                Divider().padding(.vertical, 8)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }

            Divider().padding(.vertical, 8)

            menuButton(title: "Quit Fn Dictate", systemImage: "power") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 280)
        .onAppear {
            appDelegate.openWindow = openWindow
            model.bootstrap()
            if model.showOnboarding {
                appDelegate.presentOnboarding()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(model.statusMessage)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)
            }

            if !model.partialText.isEmpty {
                Text(model.partialText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.leading, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var systemAudioRow: some View {
        Toggle(isOn: $model.includeSystemAudioInMeetings) {
            Label {
                Text("System audio")
                    .font(.body)
            } icon: {
                Image(systemName: model.includeSystemAudioInMeetings
                    ? "speaker.wave.2.fill"
                    : "speaker.slash")
                    .frame(width: 18, alignment: .center)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help("Capture Zoom/Meet/Teams audio. Requires Screen Recording.")
    }

    private var statusColor: Color {
        switch model.phase {
        case .listening, .meetingRecording: return .red
        case .processing, .meetingProcessing: return .orange
        case .idle: return .green
        }
    }

    private func menuButton(
        title: String,
        systemImage: String,
        shortcut: String? = nil,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 18, alignment: .center)
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let shortcut {
                    Text(shortcut)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint ?? .primary)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
