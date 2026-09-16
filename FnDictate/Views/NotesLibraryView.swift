import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NotesLibraryView: View {
    @Bindable var model: AppModel
    @State private var selection: MeetingNote.ID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Meetings") {
                    ForEach(model.meetings.notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title)
                                .font(.headline)
                            Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(note.id)
                        .contextMenu {
                            Button("Copy Markdown") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(note.markdownExport, forType: .string)
                            }
                            Button("Delete", role: .destructive) {
                                model.meetings.delete(note)
                                if selection == note.id { selection = nil }
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .toolbar {
                ToolbarItem {
                    Toggle("System audio", isOn: $model.includeSystemAudioInMeetings)
                        .toggleStyle(.checkbox)
                        .help("Requires Screen Recording permission")
                }
                ToolbarItem {
                    Button(model.phase == .meetingRecording ? "Stop meeting" : "Start meeting") {
                        model.toggleMeeting()
                    }
                }
            }
        } detail: {
            if let selection, let note = model.meetings.notes.first(where: { $0.id == selection }) {
                MeetingDetailView(note: note)
            } else {
                ContentUnavailableView(
                    "No meeting selected",
                    systemImage: "waveform",
                    description: Text("Start a meeting from the toolbar or menu bar.")
                )
            }
        }
        .frame(minWidth: 780, minHeight: 480)
    }
}

struct MeetingDetailView: View {
    let note: MeetingNote

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text(note.createdAt.formatted(date: .complete, time: .shortened))
                        .foregroundStyle(.secondary)
                }

                section("Overview", note.summary.isEmpty ? "No summary yet." : note.summary)

                if !note.decisions.isEmpty {
                    bulletSection("Decisions", note.decisions)
                }
                if !note.actionItems.isEmpty {
                    bulletSection("Action items", note.actionItems)
                }
                if !note.openQuestions.isEmpty {
                    bulletSection("Open questions", note.openQuestions)
                }

                section("Transcript", note.transcript.isEmpty ? "Empty transcript." : note.transcript)

                HStack {
                    Button("Copy Markdown") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(note.markdownExport, forType: .string)
                    }
                    Button("Export…") { exportMarkdown() }
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(body)
                .textSelection(.enabled)
        }
    }

    private func bulletSection(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
            ForEach(items, id: \.self) { item in
                Text("• \(item)")
                    .textSelection(.enabled)
            }
        }
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText, .text]
        panel.nameFieldStringValue = "\(note.title).md"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? note.markdownExport.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
