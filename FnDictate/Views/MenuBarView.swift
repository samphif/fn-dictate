import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.statusMessage)
                .font(.headline)
            if !model.partialText.isEmpty {
                Text(model.partialText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Divider()

            Button(model.phase == .meetingRecording ? "Stop meeting" : "Start meeting") {
                model.toggleMeeting()
            }
            .disabled(model.phase == .listening || model.phase == .processing || model.phase == .meetingProcessing)

            Toggle("Include system audio", isOn: $model.includeSystemAudioInMeetings)

            Button("Meeting notes…") {
                model.showNotes = true
                openWindow(id: "notes")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("Permissions…") {
                model.showOnboarding = true
                openWindow(id: "onboarding")
                NSApp.activate(ignoringOtherApps: true)
            }

            if let last = model.history.entries.first {
                Divider()
                Button("Copy last transcript") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(last.text, forType: .string)
                }
                Button("Paste last transcript") {
                    TextPaster.paste(last.text)
                }
            }

            if let error = model.lastError {
                Divider()
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(4)
            }

            Divider()
            Button("Quit Fn Dictate") {
                NSApp.terminate(nil)
            }
        }
        .padding(4)
        .frame(minWidth: 240)
        .onAppear {
            model.bootstrap()
            if model.showOnboarding {
                openWindow(id: "onboarding")
            }
        }
    }
}
