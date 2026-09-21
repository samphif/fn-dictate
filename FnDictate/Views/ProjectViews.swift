import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProjectMark: View {
    let project: MeetingProject
    var image: NSImage?
    var size: CGFloat = 34

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Text(project.monogram)
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: size, height: size)
        .background(Self.color(hex: project.colorHex))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .help(project.name)
    }

    static func color(hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }
}

struct ProjectsEditorSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: MeetingProject.ID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedID) {
                ForEach(model.projects.projects) { project in
                    HStack(spacing: 10) {
                        ProjectMark(
                            project: project,
                            image: model.projects.iconImage(for: project),
                            size: 28
                        )
                        Text(project.name)
                    }
                    .tag(project.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .toolbar {
                ToolbarItem {
                    Button {
                        addProject()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("New project")
                }
            }
        } detail: {
            if let project = model.projects.project(id: selectedID) {
                ProjectEditorForm(model: model, project: project)
                    .id(project.id)
            } else {
                ContentUnavailableView(
                    "No project selected",
                    systemImage: "tag",
                    description: Text("Add a project to tag notes and give each one its own icon.")
                )
            }
        }
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .onAppear {
            if selectedID == nil {
                selectedID = model.projects.projects.first?.id
            }
        }
    }

    private func addProject() {
        let project = MeetingProject(
            name: "New project",
            colorHex: ProjectPalette.nextHex(used: model.projects.projects.map(\.colorHex))
        )
        model.projects.add(project)
        selectedID = project.id
    }
}

private struct ProjectEditorForm: View {
    @Bindable var model: AppModel
    let project: MeetingProject
    @State private var name = ""
    @State private var people = ""
    @State private var keywords = ""
    @State private var usualSource = ""
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    ProjectMark(
                        project: draft,
                        image: model.projects.iconImage(for: project),
                        size: 48
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Project name", text: $name)
                            .font(.title3.weight(.semibold))
                        HStack(spacing: 8) {
                            Button("Choose icon…") { pickIcon() }
                            if project.iconFileName != nil {
                                Button("Use letters") {
                                    model.projects.clearIcon(for: project.id)
                                }
                            }
                        }
                        .font(.caption)
                    }
                }
            }

            Section {
                TextField("People", text: $people, prompt: Text("Jodi"))
                Text("Comma-separated. Action items use these names instead of guessed ones.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("People")
            }

            Section {
                TextField("Match phrases", text: $keywords, prompt: Text("architectural grille, pizza tracker"))
                Text("Untagged notes that mention one of these are tagged automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Auto-tag")
            }

            Section {
                TextField("Usual call app", text: $usualSource, prompt: Text("Zoom"))
                Text("Shown when a note didn’t capture Zoom, Teams, or Meet on its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Call")
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 28), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(ProjectPalette.hexes, id: \.self) { hex in
                        Button {
                            save(colorHex: hex)
                        } label: {
                            Circle()
                                .fill(ProjectMark.color(hex: hex))
                                .frame(width: 22, height: 22)
                                .overlay {
                                    if draft.colorHex.caseInsensitiveCompare(hex) == .orderedSame {
                                        Circle().strokeBorder(.primary, lineWidth: 2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Color")
            }

            Section {
                Button("Delete project", role: .destructive) {
                    model.clearProject(project.id)
                    model.projects.delete(project)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { reload() }
        .onDisappear { save() }
    }

    private var draft: MeetingProject {
        var copy = project
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? project.name : name
        copy.colorHex = project.colorHex
        return copy
    }

    private func reload() {
        name = project.name
        people = project.people.joined(separator: ", ")
        keywords = project.keywords.joined(separator: ", ")
        usualSource = project.usualSource ?? ""
        loaded = true
    }

    private func save(colorHex: String? = nil) {
        guard loaded else { return }
        var updated = project
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.name = trimmedName.isEmpty ? project.name : trimmedName
        updated.people = Self.list(people)
        updated.keywords = Self.list(keywords)
        let source = usualSource.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.usualSource = source.isEmpty ? nil : source
        if let colorHex {
            updated.colorHex = colorHex
        }
        model.projects.update(updated)
    }

    private func pickIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .icns, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a project icon"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.projects.setIcon(from: url, for: project.id)
    }

    private static func list(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
