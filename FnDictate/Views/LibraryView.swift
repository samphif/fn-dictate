import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Theme (adaptive light / dark)

private enum FlowTheme {
    static let canvas = Color(nsColor: .flowCanvas)
    static let sidebar = Color(nsColor: .flowSidebar)
    static let card = Color(nsColor: .flowCard)
    static let cream = Color(nsColor: .flowCream)
    static let accent = Color(nsColor: .flowAccent)
    static let accentSoft = Color(nsColor: .flowAccentSoft)
    static let ink = Color(nsColor: .flowInk)
    static let muted = Color(nsColor: .flowMuted)
    static let hairline = Color(nsColor: .flowHairline)
    /// Filled CTA (black in light, off-white in dark).
    static let solid = Color(nsColor: .flowSolid)
    static let onSolid = Color(nsColor: .flowOnSolid)
    /// Text sitting on a white chip (always dark).
    static let onLightChip = Color(red: 0.11, green: 0.11, blue: 0.11)

    static let warmGradient = LinearGradient(
        colors: [
            Color(red: 0.72, green: 0.52, blue: 0.35),
            Color(red: 0.55, green: 0.38, blue: 0.28),
            Color(red: 0.42, green: 0.30, blue: 0.24)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private extension NSColor {
    static func flowDynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    static let flowCanvas = flowDynamic(
        light: NSColor(srgbRed: 0.973, green: 0.973, blue: 0.969, alpha: 1),
        dark: NSColor(srgbRed: 0.102, green: 0.100, blue: 0.094, alpha: 1) // #1A1918
    )
    static let flowSidebar = flowDynamic(
        light: NSColor(srgbRed: 0.957, green: 0.955, blue: 0.949, alpha: 1),
        dark: NSColor(srgbRed: 0.078, green: 0.076, blue: 0.071, alpha: 1) // #141311
    )
    static let flowCard = flowDynamic(
        light: .white,
        dark: NSColor(srgbRed: 0.157, green: 0.153, blue: 0.145, alpha: 1) // #282724
    )
    static let flowCream = flowDynamic(
        light: NSColor(srgbRed: 0.953, green: 0.949, blue: 0.933, alpha: 1),
        dark: NSColor(srgbRed: 0.184, green: 0.176, blue: 0.165, alpha: 1) // #2F2D2A
    )
    static let flowAccent = flowDynamic(
        light: NSColor(srgbRed: 0.890, green: 0.839, blue: 0.757, alpha: 1),
        dark: NSColor(srgbRed: 0.420, green: 0.365, blue: 0.290, alpha: 1) // warm selected
    )
    static let flowAccentSoft = flowDynamic(
        light: NSColor(srgbRed: 0.925, green: 0.890, blue: 0.835, alpha: 1),
        dark: NSColor(srgbRed: 0.235, green: 0.210, blue: 0.175, alpha: 1)
    )
    static let flowInk = flowDynamic(
        light: NSColor(srgbRed: 0.110, green: 0.110, blue: 0.110, alpha: 1),
        dark: NSColor(srgbRed: 0.953, green: 0.945, blue: 0.925, alpha: 1) // #F3F1EC
    )
    static let flowMuted = flowDynamic(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.48)
    )
    static let flowHairline = flowDynamic(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.08),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10)
    )
    static let flowSolid = flowDynamic(
        light: .black,
        dark: NSColor(srgbRed: 0.953, green: 0.945, blue: 0.925, alpha: 1)
    )
    static let flowOnSolid = flowDynamic(
        light: .white,
        dark: NSColor(srgbRed: 0.110, green: 0.110, blue: 0.110, alpha: 1)
    )
}

// MARK: - Library

struct LibraryView: View {
    @Bindable var model: AppModel
    @State private var section: LibrarySection = .dictations
    @State private var selectedDictationID: TranscriptEntry.ID?
    @State private var selectedDictionaryID: DictionaryEntry.ID?
    @State private var selectedMeetingID: MeetingNote.ID?
    @State private var draftText = ""
    @State private var learnFromEdits = true
    @State private var formattedPreview = ""
    @State private var formattedPreviewBusy = false
    @State private var formattedPreviewGeneration = 0
    @State private var newIncorrect = ""
    @State private var newCorrect = ""
    @State private var editIncorrect = ""
    @State private var editCorrect = ""
    @State private var saveBanner: String?
    @State private var dictationSearch = ""
    @State private var dictionarySearch = ""
    @State private var meetingSearch = ""
    @State private var showDictionarySearch = false
    @State private var showAddWordSheet = false
    @State private var dismissDictationTip = false
    @State private var dismissDictionaryTip = false
    @State private var dictationFilter: DictationFilter = .all
    @State private var dictionaryFilter: DictionaryFilter = .all
    @State private var hoveredDictionaryID: DictionaryEntry.ID?
    @State private var hoveredMeetingID: MeetingNote.ID?
    @State private var remindersExportNote: MeetingNote?

    enum LibrarySection: String, CaseIterable, Identifiable {
        case dictations
        case dictionary
        case meetings
        case formatting

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .dictations: return "mic"
            case .dictionary: return "textformat"
            case .meetings: return "doc.text"
            case .formatting: return "slider.horizontal.3"
            }
        }

        var help: String {
            switch self {
            case .dictations: return "Dictations"
            case .dictionary: return "Dictionary"
            case .meetings: return "Meetings"
            case .formatting: return "Formatting"
            }
        }
    }

    private enum DictationFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case revised = "Revised"

        var id: String { rawValue }
    }

    private enum DictionaryFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case starred = "Starred"

        var id: String { rawValue }
    }

    private var firstName: String {
        let full = NSFullUserName()
        let first = full.split(separator: " ").first.map(String.init) ?? full
        return first.isEmpty ? "there" : first
    }

    var body: some View {
        HStack(spacing: 0) {
            flowSidebar
            mainPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(FlowTheme.canvas)
        .frame(minWidth: 980, minHeight: 620)
        .overlay(alignment: .top) {
            if let saveBanner {
                Text(saveBanner)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showAddWordSheet) {
            addWordSheet
        }
        .sheet(item: $remindersExportNote) { note in
            SendActionItemsToRemindersSheet(note: note, reminders: model.reminders)
        }
        .onAppear {
            applyRequestedTab()
            syncWindowTitle()
        }
        .onChange(of: model.requestedLibraryTab) { _, _ in
            applyRequestedTab()
        }
        .onChange(of: section) { _, _ in
            syncWindowTitle()
        }
    }

    /// Keep the AppKit title bar in sync with the active sidebar section.
    private func syncWindowTitle() {
        let title = section.help
        if let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue == AppModel.libraryWindowIdentifier
        }) {
            window.title = title
            return
        }
        // Hosting controller window before identifier is applied.
        NSApp.keyWindow?.title = title
    }

    // MARK: Sidebar

    private var flowSidebar: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FlowTheme.muted)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(FlowTheme.cream.opacity(0.85))
                )
                .padding(.top, 14)
                .padding(.bottom, 2)
                .accessibilityLabel("Fn Dictate")
                .accessibilityAddTraits(.isImage)
                .allowsHitTesting(false)

            Rectangle()
                .fill(FlowTheme.hairline)
                .frame(width: 18, height: 1)
                .padding(.bottom, 4)
                .accessibilityHidden(true)

            ForEach(LibrarySection.allCases) { item in
                sidebarButton(item)
            }

            Spacer()

            Button {
                if !model.permissions.microphoneGranted {
                    model.permissions.openMicrophoneSettings()
                } else if !model.permissions.accessibilityTrusted {
                    model.permissions.openAccessibilitySettings()
                } else {
                    model.permissions.openScreenRecordingSettings()
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(FlowTheme.muted)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open Privacy settings")
            .padding(.bottom, 14)
        }
        .frame(width: 64)
        .frame(maxHeight: .infinity)
        .background(FlowTheme.sidebar)
    }

    private func sidebarButton(_ item: LibrarySection) -> some View {
        let isActive = section == item
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                section = item
            }
        } label: {
            Image(systemName: item.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isActive ? FlowTheme.ink : FlowTheme.muted)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isActive ? FlowTheme.accent : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.help)
    }

    // MARK: Main panes

    @ViewBuilder
    private var mainPane: some View {
        switch section {
        case .dictations:
            dictationsPane
        case .dictionary:
            dictionaryPane
        case .meetings:
            meetingsPane
        case .formatting:
            formattingPane
        }
    }

    private func applyRequestedTab() {
        guard let tab = model.requestedLibraryTab else { return }
        switch tab {
        case .dictations: section = .dictations
        case .dictionary: section = .dictionary
        case .meetings:
            section = .meetings
            if let id = model.highlightedMeetingID {
                selectedMeetingID = id
                model.highlightedMeetingID = nil
            }
        }
        model.requestedLibraryTab = nil
    }

    // MARK: - Dictations

    private var filteredDictations: [TranscriptEntry] {
        var items = model.history.entries
        if dictationFilter == .revised {
            items = items.filter(\.isRevised)
        }
        let q = dictationSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.text.localizedCaseInsensitiveContains(q)
                || ($0.originalText?.localizedCaseInsensitiveContains(q) ?? false)
                || ($0.appName?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    private var revisedDictationCount: Int {
        model.history.entries.filter(\.isRevised).count
    }

    private var groupedDictations: [(String, [TranscriptEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredDictations) { entry -> Date in
            calendar.startOfDay(for: entry.createdAt)
        }
        return grouped.keys.sorted(by: >).map { day in
            let label = daySectionTitle(day)
            let items = grouped[day]!.sorted { $0.createdAt > $1.createdAt }
            return (label, items)
        }
    }

    private var dictationsPane: some View {
        HStack(alignment: .top, spacing: 20) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    Text("Welcome back, \(firstName)")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(FlowTheme.ink)
                        .padding(.top, 8)

                    flowSearchField(
                        placeholder: "Search dictations",
                        text: $dictationSearch
                    )

                    dictationFilterBar

                    if !dismissDictationTip {
                        dictationTipBanner
                    }

                    if filteredDictations.isEmpty {
                        emptyDictations
                    } else {
                        ForEach(groupedDictations, id: \.0) { section in
                            dictationDaySection(title: section.0, entries: section.1)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)

            dictationSideRail
                .padding(.trailing, 24)
                .padding(.top, 24)
                .padding(.bottom, 24)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private var dictationFilterBar: some View {
        HStack(spacing: 8) {
            ForEach(DictationFilter.allCases) { filter in
                Button {
                    dictationFilter = filter
                } label: {
                    HStack(spacing: 6) {
                        Text(filter.rawValue)
                            .font(.system(size: 14, weight: dictationFilter == filter ? .semibold : .regular))
                            .foregroundStyle(dictationFilter == filter ? FlowTheme.ink : FlowTheme.muted)
                        if filter == .revised, revisedDictationCount > 0 {
                            Text("\(revisedDictationCount)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(dictationFilter == filter ? FlowTheme.ink.opacity(0.7) : FlowTheme.muted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(
                                        dictationFilter == filter
                                            ? FlowTheme.ink.opacity(0.08)
                                            : FlowTheme.hairline
                                    )
                                )
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(dictationFilter == filter ? FlowTheme.ink : Color.clear)
                            .frame(height: 2)
                            .offset(y: 8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var dictationTipBanner: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(FlowTheme.warmGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.black.opacity(0.15), .black.opacity(0.35)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Working around other people?")
                        .font(.system(size: 26, weight: .regular, design: .serif))
                        .foregroundStyle(.white)
                    Text("Hold Fn to dictate quietly into any app — no meeting required.")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        dismissDictationTip = true
                    } label: {
                        Text("Got it")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(FlowTheme.onLightChip)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                Spacer(minLength: 24)
            }
            .padding(28)

            Button {
                dismissDictationTip = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(14)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 150)
    }

    private func dictationDaySection(title: String, entries: [TranscriptEntry]) -> some View {
        let lastID = entries.last?.id
        return VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FlowTheme.muted)
                .tracking(0.6)
                .padding(.bottom, 10)

            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    DictationRowView(
                        entry: entry,
                        selected: selectedDictationID == entry.id,
                        showDivider: entry.id != lastID,
                        onSelect: { openDictationEditor(entry) },
                        onCopy: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.text, forType: .string)
                            flash("Copied")
                        },
                        onPaste: { TextPaster.paste(entry.text) },
                        onDelete: {
                            model.history.delete(entry)
                            if selectedDictationID == entry.id {
                                selectedDictationID = nil
                                draftText = ""
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 4)
            .background(FlowTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(FlowTheme.hairline, lineWidth: 1)
            )
        }
    }

    private var emptyDictations: some View {
        let searching = !dictationSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let filteringRevised = dictationFilter == .revised
        let title: String
        let subtitle: String
        let icon: String
        if searching {
            title = "No matches"
            subtitle = "Try a different search."
            icon = "magnifyingglass"
        } else if filteringRevised {
            title = "No revisions yet"
            subtitle = "Edit a dictation to keep the original and mark it as revised."
            icon = "pencil.line"
        } else {
            title = "No dictations yet"
            subtitle = "Hold Fn to dictate. Your transcripts will show up here."
            icon = "waveform"
        }
        return VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(FlowTheme.muted)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(FlowTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
        .background(FlowTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FlowTheme.hairline, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var dictationSideRail: some View {
        VStack(spacing: 14) {
            if let id = selectedDictationID,
               let entry = model.history.entries.first(where: { $0.id == id })
            {
                dictationEditCard(entry)
            } else {
                statsCard
                dictionaryPromoCard
            }
        }
        .frame(width: 320)
    }

    private func openDictationEditor(_ entry: TranscriptEntry) {
        withAnimation(.easeInOut(duration: 0.22)) {
            selectedDictationID = entry.id
            draftText = entry.text
            formattedPreview = ""
            formattedPreviewBusy = false
        }
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            statRow(value: formattedWordCount, label: "total words")
            statRow(value: "\(model.history.entries.count)", label: "dictations")
            statRow(value: "\(dictationStreak)", label: dictationStreak == 1 ? "day streak" : "day streak")
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FlowTheme.cream, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func statRow(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(FlowTheme.ink)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(FlowTheme.muted)
        }
    }

    private var dictionaryPromoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dictionary")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FlowTheme.ink)
            Text(model.dictionary.entries.isEmpty
                  ? "Add names and jargon so they’re spelled right."
                  : "\(model.dictionary.entries.count) personal term\(model.dictionary.entries.count == 1 ? "" : "s")")
                .font(.system(size: 13))
                .foregroundStyle(FlowTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                section = .dictionary
            } label: {
                Text("Open dictionary")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FlowTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(FlowTheme.card, in: Capsule())
                    .overlay(Capsule().stroke(FlowTheme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FlowTheme.accentSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func dictationEditCard(_ entry: TranscriptEntry) -> some View {
        let baseline = entry.text
        let compareFrom = entry.originalText ?? baseline
        let compareTo = draftText
        // Only surface ASR→text cleanup when the user hasn't revised yet, and label it clearly.
        let speechCleanupSpans = (!entry.isRevised && draftText == entry.text)
            ? DictionaryStore.revisionSpans(from: compareFrom, to: compareTo)
            : []
        let editSpans = (draftText != entry.text)
            ? DictionaryStore.revisionSpans(from: entry.text, to: draftText)
            : (entry.isRevised
                ? DictionaryStore.revisionSpans(from: compareFrom, to: compareTo)
                : [])
        let corrections = learnFromEdits && draftText != baseline
            ? model.dictionary.previewCorrections(from: baseline, to: draftText)
            : []

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Edit")
                            .font(.system(size: 15, weight: .semibold))
                        if entry.isRevised {
                            Text("Revised")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(FlowTheme.ink.opacity(0.75))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(FlowTheme.accentSoft, in: Capsule())
                        }
                    }
                    HStack(spacing: 6) {
                        Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                        if let appName = entry.appName {
                            Text("·")
                            Text(appName)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(FlowTheme.muted)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        selectedDictationID = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(FlowTheme.muted)
                        .frame(width: 24, height: 24)
                        .background(FlowTheme.card.opacity(0.7), in: Circle())
                }
                .buttonStyle(.plain)
            }

            Toggle("Learn corrections", isOn: $learnFromEdits)
                .toggleStyle(.checkbox)
                .font(.caption)

            if !speechCleanupSpans.isEmpty {
                revisionDiffSection(
                    title: "From speech",
                    spans: speechCleanupSpans,
                    footnote: nil
                )
            }

            if !editSpans.isEmpty, entry.isRevised || draftText != entry.text {
                revisionDiffSection(
                    title: "Changes",
                    spans: editSpans,
                    footnote: learnFromEdits && !corrections.isEmpty
                        ? "Saving will learn matching corrections."
                        : nil
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Text")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FlowTheme.muted)
                    .tracking(0.4)

                TextEditor(text: $draftText)
                    .font(.system(size: 13))
                    .foregroundStyle(FlowTheme.ink)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 140, maxHeight: 240)
                    .background(FlowTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(FlowTheme.hairline, lineWidth: 1)
                    )
            }
            .onChange(of: draftText) { _, _ in
                scheduleFormattedPreview(for: entry)
            }
            .onChange(of: model.toneSettingsVersion) { _, _ in
                scheduleFormattedPreview(for: entry)
            }
            .onAppear {
                scheduleFormattedPreview(for: entry)
            }

            formattedPreviewSection(for: entry)

            // Further edits on an already-revised entry — learn from current → draft only.
            if !corrections.isEmpty, entry.isRevised {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Will learn")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FlowTheme.muted)
                        .tracking(0.4)

                    ForEach(Array(corrections.enumerated()), id: \.offset) { _, pair in
                        revisionChangeChip(removed: pair.incorrect, added: pair.correct)
                    }
                }
            }

            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(draftText, forType: .string)
                }
                .buttonStyle(.borderless)

                if let raw = entry.originalText?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !raw.isEmpty,
                   draftText != raw
                {
                    Button("Undo cleanup") {
                        draftText = raw
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()

                Button("Save") {
                    saveDictationEdit(entry)
                }
                .buttonStyle(.borderedProminent)
                .tint(FlowTheme.solid)
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || draftText == entry.text)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FlowTheme.cream, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func formattedPreviewSection(for entry: TranscriptEntry) -> some View {
        let tone = model.effectiveTone(bundleID: entry.appBundleID, name: entry.appName)
        let appLabel = entry.appName.map { AppDisplayName.short(name: $0, bundleID: entry.appBundleID) } ?? "this app"

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Formatted")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FlowTheme.muted)
                    .tracking(0.4)
                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(FlowTheme.muted.opacity(0.6))
                Text("\(tone.displayName) for \(appLabel)")
                    .font(.system(size: 11))
                    .foregroundStyle(FlowTheme.muted)
                    .lineLimit(1)
                if formattedPreviewBusy {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.leading, 2)
                }
            }

            if tone == .raw {
                Text("Paste stays near-raw for this app. Change the level in Formatting to preview Light or Polished cleanup.")
                    .font(.system(size: 12))
                    .foregroundStyle(FlowTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(formattedPreview.isEmpty ? draftText : formattedPreview)
                .font(.system(size: 13))
                .foregroundStyle(FlowTheme.ink.opacity(tone == .raw ? 0.7 : 1))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .frame(minHeight: 72, maxHeight: 160, alignment: .topLeading)
                .background(FlowTheme.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(FlowTheme.hairline, lineWidth: 1)
                )
                .textSelection(.enabled)
        }
    }

    private func scheduleFormattedPreview(for entry: TranscriptEntry) {
        formattedPreviewGeneration += 1
        let generation = formattedPreviewGeneration
        let source = draftText
        let tone = model.effectiveTone(bundleID: entry.appBundleID, name: entry.appName)

        let basic = TextCleaner.basicCleanup(source)
        if tone == .raw || !CleanupFidelity.shouldUseModel(basic) {
            formattedPreviewBusy = false
            formattedPreview = basic
            return
        }

        formattedPreviewBusy = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard generation == formattedPreviewGeneration else { return }
            let cleaned = await model.cleanedText(source, tone: tone)
            guard generation == formattedPreviewGeneration else { return }
            formattedPreview = cleaned
            formattedPreviewBusy = false
        }
    }

    private func revisionDiffSection(
        title: String,
        spans: [(removed: String, added: String)],
        footnote: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FlowTheme.muted)
                .tracking(0.4)

            ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                revisionChangeChip(removed: span.removed, added: span.added)
            }

            if let footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(FlowTheme.muted)
            }
        }
    }

    private func revisionChangeChip(removed: String, added: String) -> some View {
        HStack(spacing: 8) {
            if removed.isEmpty {
                Text("added")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FlowTheme.muted)
            } else {
                Text(removed)
                    .strikethrough()
                    .foregroundStyle(FlowTheme.muted)
            }

            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(FlowTheme.muted)

            if added.isEmpty {
                Text("removed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FlowTheme.muted)
            } else {
                Text(added)
                    .fontWeight(.semibold)
                    .foregroundStyle(FlowTheme.ink)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FlowTheme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var totalWordCount: Int {
        model.history.entries.reduce(0) { partial, entry in
            partial + entry.text.split { $0.isWhitespace || $0.isNewline }.count
        }
    }

    private var formattedWordCount: String {
        let count = totalWordCount
        if count >= 1_000 {
            let k = Double(count) / 1_000.0
            return String(format: k >= 10 ? "%.0fK" : "%.1fK", k)
        }
        return "\(count)"
    }

    private var dictationStreak: Int {
        let calendar = Calendar.current
        let days = Set(model.history.entries.map { calendar.startOfDay(for: $0.createdAt) })
        guard !days.isEmpty else { return 0 }
        var streak = 0
        var cursor = calendar.startOfDay(for: .now)
        // Allow streak to start from yesterday if nothing today yet.
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(yesterday)
            else { return 0 }
            cursor = yesterday
        }
        while days.contains(cursor) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    private func saveDictationEdit(_ entry: TranscriptEntry) {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let baseline = entry.text
        var updated = entry
        if updated.originalText == nil {
            updated.originalText = entry.text
        }
        updated.text = trimmed
        updated.updatedAt = .now
        model.history.update(updated)

        var banner = "Saved"
        if learnFromEdits {
            if baseline == trimmed {
                banner = "Saved · no changes to learn"
            } else {
                let learned = model.dictionary.learn(from: baseline, to: trimmed)
                if learned > 0 {
                    banner = "Saved · learned \(learned) correction\(learned == 1 ? "" : "s")"
                } else {
                    banner = "Saved · couldn’t auto-detect word fixes — add them in Dictionary"
                }
            }
        }
        flash(banner)
    }

    // MARK: - Formatting

    private var formattingPane: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Text("Formatting")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(FlowTheme.ink)
                    .padding(.top, 8)

                Text("How much cleanup runs before paste into each app. Raw is near-verbatim; Light removes fillers and fixes punctuation; Polished may reword for clarity but never invents content. Very short dictations skip the model.")
                    .font(.system(size: 13))
                    .foregroundStyle(FlowTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    ForEach(Array(model.formattingProfiles.enumerated()), id: \.element.id) { index, profile in
                        formattingProfileRow(profile)
                        if index < model.formattingProfiles.count - 1 {
                            Divider()
                                .overlay(FlowTheme.hairline)
                                .padding(.leading, 52)
                        }
                    }
                }
                .padding(.vertical, 4)
                .background(FlowTheme.cream, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func formattingProfileRow(_ profile: FormattingProfile) -> some View {
        HStack(spacing: 12) {
            formattingAppIcon(profile)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FlowTheme.ink)
                    if profile.isOverride {
                        Text("Custom")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(FlowTheme.ink.opacity(0.7))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(FlowTheme.accentSoft, in: Capsule())
                    }
                    if profile.isCatchAll {
                        Text("Default")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(FlowTheme.muted)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(FlowTheme.card, in: Capsule())
                    }
                }
                if let bundleID = profile.bundleID {
                    Text(bundleID)
                        .font(.system(size: 11))
                        .foregroundStyle(FlowTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Apps without a specific rule")
                        .font(.system(size: 11))
                        .foregroundStyle(FlowTheme.muted)
                }
            }

            Spacer(minLength: 8)

            if profile.canEdit, let bundleID = profile.bundleID {
                Picker("Tone", selection: toneBinding(for: bundleID, name: profile.name)) {
                    ForEach(CleanupTone.allCases, id: \.self) { tone in
                        Text(tone.displayName).tag(tone)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)

                if profile.isOverride {
                    Button("Reset") {
                        model.resetTone(forBundleID: bundleID)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FlowTheme.muted)
                }
            } else {
                Text(profile.tone.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FlowTheme.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(FlowTheme.card, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func toneBinding(for bundleID: String, name: String) -> Binding<CleanupTone> {
        Binding(
            get: { model.effectiveTone(bundleID: bundleID, name: name) },
            set: { model.setTone($0, forBundleID: bundleID) }
        )
    }

    @ViewBuilder
    private func formattingAppIcon(_ profile: FormattingProfile) -> some View {
        if profile.isCatchAll {
            Image(systemName: "app.dashed")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FlowTheme.muted)
                .frame(width: 28, height: 28)
                .background(FlowTheme.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else if let icon = AppIconCache.icon(bundleID: profile.bundleID, appName: profile.name) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            Image(systemName: "app")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FlowTheme.muted)
                .frame(width: 28, height: 28)
                .background(FlowTheme.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    // MARK: - Dictionary

    private var filteredDictionary: [DictionaryEntry] {
        var items = model.dictionary.entries
        if dictionaryFilter == .starred {
            items = items.filter(\.isStarred)
        }
        let q = dictionarySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            items = items.filter {
                $0.correct.localizedCaseInsensitiveContains(q)
                    || $0.incorrect.localizedCaseInsensitiveContains(q)
            }
        }
        return items.sorted {
            $0.correct.localizedCaseInsensitiveCompare($1.correct) == .orderedAscending
        }
    }

    private var dictionaryPane: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Dictionary")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(FlowTheme.ink)
                    Spacer()
                    Button {
                        newIncorrect = ""
                        newCorrect = ""
                        showAddWordSheet = true
                    } label: {
                        Text("Add new")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(FlowTheme.onSolid)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(FlowTheme.solid, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)

                HStack(spacing: 8) {
                    ForEach(DictionaryFilter.allCases) { filter in
                        Button {
                            dictionaryFilter = filter
                        } label: {
                            VStack(spacing: 6) {
                                Text(filter.rawValue)
                                    .font(.system(size: 14, weight: dictionaryFilter == filter ? .semibold : .regular))
                                    .foregroundStyle(dictionaryFilter == filter ? FlowTheme.ink : FlowTheme.muted)
                                Rectangle()
                                    .fill(dictionaryFilter == filter ? FlowTheme.ink : Color.clear)
                                    .frame(height: 2)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Button {
                        withAnimation { showDictionarySearch.toggle() }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(FlowTheme.muted)
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if showDictionarySearch {
                    flowSearchField(placeholder: "Search dictionary", text: $dictionarySearch)
                }

                if !dismissDictionaryTip {
                    dictionaryTipBanner
                }

                Toggle(isOn: $model.learnFromInAppCorrections) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Learn from in-app corrections")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(FlowTheme.ink)
                        Text("After paste, watch the focused field for spelling fixes. In Cursor, if the field can’t be read, select-all and copy (⌘A ⌘C) after editing — or fix in Library.")
                            .font(.system(size: 12))
                            .foregroundStyle(FlowTheme.muted)
                    }
                }
                .toggleStyle(.switch)
                .padding(14)
                .background(FlowTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(FlowTheme.hairline, lineWidth: 1)
                )

                dictionaryListCard
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var dictionaryTipBanner: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(FlowTheme.warmGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.black.opacity(0.12), .black.opacity(0.38)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )

            VStack(alignment: .leading, spacing: 12) {
                Text("Fn Dictate spells the way *you* do.")
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundStyle(.white)

                Text("Correct a spelling once in any app after paste, or add it here — company jargon and uncommon names stay spelled right.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        showAddWordSheet = true
                    } label: {
                        Text("Add new word")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(FlowTheme.onLightChip)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    ForEach(dictionaryPreviewPills, id: \.self) { word in
                        Text(word)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.white.opacity(0.18), in: Capsule())
                    }
                }
                .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                dismissDictionaryTip = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(14)
        }
        .frame(minHeight: 180)
    }

    private var dictionaryPreviewPills: [String] {
        let fromDict = model.dictionary.entries.prefix(4).map(\.correct)
        if fromDict.isEmpty {
            return ["RemyCare", "Fn", "⌥M"]
        }
        return Array(fromDict)
    }

    private var dictionaryListCard: some View {
        Group {
            if filteredDictionary.isEmpty {
                VStack(spacing: 10) {
                    Text(model.dictionary.entries.isEmpty ? "Dictionary is empty" : "No matches")
                        .font(.headline)
                    Text(model.dictionary.entries.isEmpty
                         ? "Add a preferred spelling (names, jargon) even before it is misheard, or fix a misspelling after paste with Learn from in-app corrections on."
                         : "Try a different filter or search.")
                        .font(.subheadline)
                        .foregroundStyle(FlowTheme.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 56)
                .background(FlowTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(FlowTheme.hairline, lineWidth: 1)
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredDictionary.enumerated()), id: \.element.id) { index, entry in
                        dictionaryRow(entry)
                        if index < filteredDictionary.count - 1 {
                            Rectangle()
                                .fill(FlowTheme.hairline)
                                .frame(height: 1)
                                .padding(.leading, 16)
                        }
                    }
                }
                .background(FlowTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(FlowTheme.hairline, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.03), radius: 8, y: 2)
            }
        }
    }

    private func dictionaryRow(_ entry: DictionaryEntry) -> some View {
        let selected = selectedDictionaryID == entry.id
        let hovered = hoveredDictionaryID == entry.id
        let showActions = selected || hovered
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    if entry.isHintOnly {
                        Text(entry.correct)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(FlowTheme.ink)
                            .lineLimit(1)
                        Text("preferred")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FlowTheme.muted)
                    } else {
                        Text(entry.incorrect)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(FlowTheme.muted)
                            .lineLimit(1)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(FlowTheme.muted.opacity(0.7))
                        Text(entry.correct)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(FlowTheme.ink)
                            .lineLimit(1)
                    }
                    if entry.isStarred {
                        Text("✨")
                            .font(.system(size: 11))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    entry.isHintOnly
                        ? "Preferred spelling \(entry.correct)"
                        : "\(entry.incorrect) goes to \(entry.correct)"
                )
                Spacer(minLength: 12)
                // Always reserve trailing space so hover/selection doesn't reflow text.
                HStack(spacing: 10) {
                    iconAction(entry.isStarred ? "star.fill" : "star") {
                        model.dictionary.toggleStar(entry)
                    }
                    iconAction("pencil") {
                        selectedDictionaryID = entry.id
                        editIncorrect = entry.incorrect
                        editCorrect = entry.correct
                    }
                    iconAction("trash") {
                        model.dictionary.delete(entry)
                        if selectedDictionaryID == entry.id {
                            selectedDictionaryID = nil
                        }
                    }
                }
                .opacity(showActions ? 1 : 0)
                .allowsHitTesting(showActions)
                .accessibilityHidden(!showActions)
            }

            if selected {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("Heard / incorrect (optional)", text: $editIncorrect)
                            .textFieldStyle(.roundedBorder)
                        TextField("Correct spelling", text: $editCorrect)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Button("Delete", role: .destructive) {
                            model.dictionary.delete(entry)
                            selectedDictionaryID = nil
                            flash("Removed from dictionary")
                        }
                        Spacer()
                        Button("Save") {
                            saveDictionaryEdit(entry)
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSaveDictionaryEdit(entry))
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(selected ? FlowTheme.cream.opacity(0.7) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredDictionaryID = hovering ? entry.id : (hoveredDictionaryID == entry.id ? nil : hoveredDictionaryID)
        }
        .onTapGesture {
            selectedDictionaryID = entry.id
            editIncorrect = entry.incorrect
            editCorrect = entry.correct
        }
        .contextMenu {
            Button(entry.isStarred ? "Unstar" : "Star") {
                model.dictionary.toggleStar(entry)
            }
            Button("Delete", role: .destructive) {
                model.dictionary.delete(entry)
                if selectedDictionaryID == entry.id { selectedDictionaryID = nil }
            }
        }
    }

    private var addWordSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add new word")
                .font(.title2.weight(.semibold))
            Text("Add a preferred spelling, or map what speech recognition hears to the spelling you want.")
                .foregroundStyle(FlowTheme.muted)

            Form {
                TextField("Heard / incorrect (optional)", text: $newIncorrect)
                TextField("Correct spelling", text: $newCorrect)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { showAddWordSheet = false }
                Spacer()
                Button("Add to dictionary") {
                    let incorrect = newIncorrect
                    let correct = newCorrect
                    model.dictionary.add(incorrect: incorrect, correct: correct)
                    showAddWordSheet = false
                    flash("Added to dictionary")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newCorrect.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func canSaveDictionaryEdit(_ entry: DictionaryEntry) -> Bool {
        let incorrect = editIncorrect.trimmingCharacters(in: .whitespacesAndNewlines)
        let correct = editCorrect.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !correct.isEmpty else { return false }
        if !incorrect.isEmpty, incorrect.caseInsensitiveCompare(correct) == .orderedSame {
            return false
        }
        return incorrect != entry.incorrect || correct != entry.correct
    }

    private func saveDictionaryEdit(_ entry: DictionaryEntry) {
        let incorrect = editIncorrect.trimmingCharacters(in: .whitespacesAndNewlines)
        let correct = editCorrect.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSaveDictionaryEdit(entry) else { return }
        var updated = entry
        updated.incorrect = incorrect.caseInsensitiveCompare(correct) == .orderedSame ? "" : incorrect
        updated.correct = correct
        model.dictionary.update(updated)
        flash("Saved")
    }

    // MARK: - Meetings

    private var filteredMeetings: [MeetingNote] {
        let q = meetingSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return model.meetings.notes }
        return model.meetings.notes.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.summary.localizedCaseInsensitiveContains(q)
                || $0.transcript.localizedCaseInsensitiveContains(q)
        }
    }

    private var groupedMeetings: [(String, [MeetingNote])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredMeetings) { note -> Date in
            calendar.startOfDay(for: note.createdAt)
        }
        return grouped.keys.sorted(by: >).map { day in
            let label = daySectionTitle(day, includeWeekday: true)
            let items = grouped[day]!.sorted { $0.createdAt > $1.createdAt }
            return (label, items)
        }
    }

    private var meetingsPane: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("Notetaker")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(FlowTheme.ink)
                        Spacer()
                        Button {
                            model.toggleMeeting()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: model.phase == .meetingRecording
                                      ? "stop.fill" : "plus")
                                Text(model.phase == .meetingRecording ? "Stop meeting" : "New note")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(model.phase == .meetingRecording ? .white : FlowTheme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(model.phase == .meetingRecording ? Color.red : FlowTheme.card)
                            )
                            .overlay(
                                Capsule().stroke(FlowTheme.hairline, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Shortcut: ⌥M")

                        Toggle(isOn: $model.includeSystemAudioInMeetings) {
                            Image(systemName: model.includeSystemAudioInMeetings
                                  ? "speaker.wave.2.fill" : "speaker.slash")
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.borderless)
                        .help("Capture Zoom/Meet/Teams audio. Requires Screen Recording.")

                        Toggle(isOn: $model.autoStopRecordingWhenMeetingEnds) {
                            Image(systemName: model.autoStopRecordingWhenMeetingEnds
                                  ? "stop.circle.fill" : "stop.circle")
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.borderless)
                        .help("Auto-stop recording when the Zoom/Teams/Meet call ends.")
                    }
                    .padding(.top, 8)

                    flowSearchField(
                        placeholder: "Ask across meetings… or filter notes",
                        text: $meetingSearch,
                        onSubmit: {
                            let q = meetingSearch.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard looksLikeQuestion(q) else { return }
                            model.askMeetings(question: q)
                        }
                    )

                    if model.meetingAskBusy {
                        Text("Thinking…")
                            .font(.caption)
                            .foregroundStyle(FlowTheme.muted)
                    } else if let answer = model.meetingAskAnswer {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Answer")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(FlowTheme.muted)
                                Spacer()
                                Button("Dismiss") {
                                    model.meetingAskAnswer = nil
                                }
                                .buttonStyle(.plain)
                                .font(.caption)
                            }
                            Text(answer)
                                .font(.system(size: 13))
                                .foregroundStyle(FlowTheme.ink)
                                .textSelection(.enabled)
                        }
                        .padding(14)
                        .background(FlowTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(FlowTheme.hairline, lineWidth: 1)
                        )
                    }

                    meetingsDayCard

                    if model.phase == .meetingRecording || model.phase == .meetingProcessing {
                        liveTranscriptCard
                    }

                    HStack {
                        Text("My notes")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Button {
                            model.revealAgentExportFolder()
                        } label: {
                            Label("Agent export", systemImage: "folder")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.borderless)
                        .help("Open MCP-ready markdown export folder")
                    }
                    .padding(.top, 4)

                    if filteredMeetings.isEmpty {
                        emptyMeetings
                    } else {
                        ForEach(groupedMeetings, id: \.0) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.0)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(FlowTheme.muted)
                                    .tracking(0.5)
                                ForEach(group.1) { note in
                                    meetingRow(note)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
            .frame(maxWidth: .infinity)

            meetingPreviewRail
                .padding(20)
        }
    }

    private var meetingsDayCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("\(firstName.uppercased())’S DAY", systemImage: "sun.max")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FlowTheme.muted)
                    .labelStyle(.titleAndIcon)
                Spacer()
                if !model.calendar.isAuthorized {
                    Button("Connect Calendar") {
                        Task { await model.requestCalendarAccess() }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.borderless)
                } else {
                    Button("Refresh brief") {
                        Task { await model.refreshUpcomingBriefIfNeeded() }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .buttonStyle(.borderless)
                }
            }

            if model.phase == .meetingRecording {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Circle().fill(.red).frame(width: 8, height: 8)
                        Text("Recording…")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Button("Catch up") { model.catchUpOnActiveMeeting() }
                            .buttonStyle(.bordered)
                        Button("Stop") { model.toggleMeeting() }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                    }
                    if let catchUp = model.meetingCatchUp, !catchUp.isEmpty {
                        Text(catchUp)
                            .font(.system(size: 13))
                            .foregroundStyle(FlowTheme.ink.opacity(0.9))
                            .textSelection(.enabled)
                    }
                }
                .padding(16)
                .background(FlowTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if let cal = model.upcomingCalendarMeeting {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundStyle(FlowTheme.muted)
                        Text(cal.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(FlowTheme.ink)
                        Spacer()
                        Text(cal.startDate.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(FlowTheme.muted)
                    }
                    if !cal.attendees.isEmpty {
                        Text(cal.attendees.joined(separator: " · "))
                            .font(.system(size: 12))
                            .foregroundStyle(FlowTheme.muted)
                            .lineLimit(2)
                    }
                    if let brief = model.upcomingBrief, !brief.isEmpty {
                        Text(brief)
                            .font(.system(size: 13))
                            .foregroundStyle(FlowTheme.ink.opacity(0.88))
                            .lineLimit(8)
                            .textSelection(.enabled)
                    }
                    HStack {
                        Button {
                            model.toggleMeeting()
                        } label: {
                            Text("Start meeting")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(FlowTheme.onSolid)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(FlowTheme.solid, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }
                .padding(16)
                .background(FlowTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(FlowTheme.muted)
                    Text(model.calendar.isAuthorized
                         ? "No upcoming calendar meetings"
                         : "Connect Calendar for speaker names & briefs")
                        .font(.subheadline)
                        .foregroundStyle(FlowTheme.muted)
                    Button {
                        model.toggleMeeting()
                    } label: {
                        Text("Start meeting")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(FlowTheme.onSolid)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(FlowTheme.solid, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(FlowTheme.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(16)
        .background(FlowTheme.cream.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear {
            model.refreshUpcomingCalendar()
            Task { await model.refreshUpcomingBriefIfNeeded() }
        }
    }

    private var liveTranscriptCard: some View {
        let liveNote = model.activeMeetingID.flatMap { id in
            model.meetings.notes.first(where: { $0.id == id })
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Live transcript")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if model.phase == .meetingProcessing {
                    Text("Re-reading…")
                        .font(.caption)
                        .foregroundStyle(FlowTheme.muted)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let liveNote, !liveNote.segments.isEmpty {
                        ForEach(liveNote.segments.sorted(by: { $0.startOffset < $1.startOffset })) { seg in
                            HStack(alignment: .top, spacing: 8) {
                                Text(seg.speaker)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(FlowTheme.muted)
                                    .frame(width: 56, alignment: .leading)
                                Text(seg.text)
                                    .font(.system(size: 13))
                                    .foregroundStyle(FlowTheme.ink)
                                    .textSelection(.enabled)
                            }
                        }
                    } else if !model.partialText.isEmpty {
                        Text(model.partialText)
                            .font(.system(size: 13))
                            .foregroundStyle(FlowTheme.ink)
                    } else {
                        Text("Listening for speech…")
                            .font(.system(size: 13))
                            .foregroundStyle(FlowTheme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
        }
        .padding(16)
        .background(FlowTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(FlowTheme.hairline, lineWidth: 1)
        )
    }

    private func looksLikeQuestion(_ text: String) -> Bool {
        let q = text.lowercased()
        if text.contains("?") { return true }
        let starters = ["who", "what", "when", "where", "why", "how", "did", "does", "do ", "is ", "are ", "was ", "were ", "which", "summarize", "list "]
        return starters.contains { q.hasPrefix($0) }
    }

    private func meetingRow(_ note: MeetingNote) -> some View {
        let selected = selectedMeetingID == note.id
        let metaParts: [String] = {
            var parts = [note.createdAt.formatted(date: .omitted, time: .shortened).lowercased()]
            if let duration = note.formattedDuration {
                parts.append(duration)
            }
            if note.wordCount > 0 {
                parts.append(note.formattedWordCount)
            }
            return parts
        }()
        let actionPreview = note.actionItems.first

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(FlowTheme.muted)
                .frame(width: 34, height: 34)
                .background(FlowTheme.cream, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FlowTheme.ink)
                    .lineLimit(1)

                Text(metaParts.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(FlowTheme.muted)
                    .lineLimit(1)

                if note.processingState == .processing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text(note.processingMessage ?? "Processing notes…")
                            .font(.system(size: 12))
                            .foregroundStyle(FlowTheme.muted)
                            .lineLimit(1)
                    }
                } else if let actionPreview {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "checklist")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(FlowTheme.muted)
                        Text(actionPreview)
                            .font(.system(size: 12))
                            .foregroundStyle(FlowTheme.ink.opacity(0.82))
                            .lineLimit(1)
                        if note.actionItems.count > 1 {
                            Text("+\(note.actionItems.count - 1)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(FlowTheme.muted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(FlowTheme.hairline, in: Capsule())
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        note.actionItems.count == 1
                            ? "1 action item: \(actionPreview)"
                            : "\(note.actionItems.count) action items. First: \(actionPreview)"
                    )
                }
            }
            Spacer(minLength: 8)

            if !note.actionItems.isEmpty {
                Text("\(note.actionItems.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FlowTheme.ink.opacity(0.75))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(FlowTheme.accentSoft, in: Capsule())
                    .help("\(note.actionItems.count) action item\(note.actionItems.count == 1 ? "" : "s")")
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? FlowTheme.cream : (hoveredMeetingID == note.id ? FlowTheme.card : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredMeetingID = hovering ? note.id : (hoveredMeetingID == note.id ? nil : hoveredMeetingID)
        }
        .onTapGesture { selectedMeetingID = note.id }
        .contextMenu {
            Button("Copy Markdown") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(note.markdownExport, forType: .string)
            }
            if !note.actionItems.isEmpty {
                Button("Send action items to Reminders…") {
                    selectedMeetingID = note.id
                    remindersExportNote = note
                }
            }
            Button("Delete", role: .destructive) {
                model.meetings.delete(note)
                if selectedMeetingID == note.id { selectedMeetingID = nil }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var emptyMeetings: some View {
        VStack(spacing: 10) {
            Text("No notes yet")
                .font(.headline)
            Text("Press ⌥M to start a meeting, or use New note.")
                .font(.subheadline)
                .foregroundStyle(FlowTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    @ViewBuilder
    private var meetingPreviewRail: some View {
        if let id = selectedMeetingID,
           let note = model.meetings.notes.first(where: { $0.id == id })
        {
            MeetingPreviewCard(noteID: note.id, model: model)
                .frame(width: 320)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(FlowTheme.muted)
                Text("Select a note")
                    .font(.subheadline)
                    .foregroundStyle(FlowTheme.muted)
            }
            .frame(width: 320)
            .frame(maxHeight: .infinity)
            .background(FlowTheme.cream, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    // MARK: - Shared helpers

    private func flowSearchField(
        placeholder: String,
        text: Binding<String>,
        onSubmit: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FlowTheme.muted)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .onSubmit { onSubmit?() }

            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(FlowTheme.muted)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(FlowTheme.cream, in: Capsule())
        .overlay(
            Capsule()
                .stroke(FlowTheme.hairline, lineWidth: 1)
        )
    }

    private func iconAction(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FlowTheme.muted)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
    }

    private func daySectionTitle(_ day: Date, includeWeekday: Bool = false) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) {
            if includeWeekday {
                return "TODAY, \(day.formatted(.dateTime.month(.abbreviated).day()).uppercased())"
            }
            return "TODAY"
        }
        if calendar.isDateInYesterday(day) {
            return "YESTERDAY"
        }
        if includeWeekday {
            return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased()
        }
        return day.formatted(.dateTime.month(.abbreviated).day()).uppercased()
    }

    private func flash(_ message: String) {
        withAnimation {
            saveBanner = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation {
                if saveBanner == message { saveBanner = nil }
            }
        }
    }
}

// MARK: - Dictation row (isolated hover + cached icons)

@MainActor
private enum AppIconCache {
    private static var icons: [String: NSImage] = [:]
    private static var misses: Set<String> = []

    static func icon(bundleID: String?, appName: String?) -> NSImage? {
        let key = bundleID ?? appName ?? ""
        guard !key.isEmpty else { return nil }
        if let cached = icons[key] { return cached }
        if misses.contains(key) { return nil }

        let resolved: NSImage?
        if let bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        {
            resolved = NSWorkspace.shared.icon(forFile: url.path)
        } else if let appName,
                  let app = NSWorkspace.shared.runningApplications.first(where: {
                      $0.localizedName?.caseInsensitiveCompare(appName) == .orderedSame
                  }),
                  let bundleURL = app.bundleURL
        {
            resolved = NSWorkspace.shared.icon(forFile: bundleURL.path)
        } else {
            resolved = nil
        }

        if let resolved {
            icons[key] = resolved
        } else {
            misses.insert(key)
        }
        return resolved
    }
}

private struct DictationRowView: View {
    let entry: TranscriptEntry
    let selected: Bool
    let showDivider: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    private var showActions: Bool { selected || isHovered }

    private var timeLabel: String {
        entry.createdAt.formatted(date: .omitted, time: .shortened).lowercased()
    }

    private var appLabel: String {
        AppDisplayName.short(name: entry.appName, bundleID: entry.appBundleID)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Text(timeLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(FlowTheme.muted)
                    .frame(width: 64, alignment: .leading)
                    .padding(.top, 2)

                appBadge
                    .padding(.top, 1)

                Text(entry.text)
                    .font(.system(size: 14))
                    .foregroundStyle(FlowTheme.ink)
                    .lineLimit(selected ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                if entry.isRevised {
                    Text("Revised")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(FlowTheme.ink.opacity(0.75))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(FlowTheme.accentSoft, in: Capsule())
                        .help("This dictation was edited from the original transcript")
                        .padding(.top, 1)
                }

                // Always reserve trailing space so hover/selection doesn't reflow text.
                HStack(spacing: 10) {
                    rowIconButton("doc.on.doc", action: onCopy)
                    rowIconButton("pencil", action: onSelect)
                    Menu {
                        Button("Paste into frontmost app", action: onPaste)
                        Button("Delete", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(FlowTheme.muted)
                    }
                }
                .padding(.top, 2)
                .opacity(showActions ? 1 : 0)
                .allowsHitTesting(showActions)
                .accessibilityHidden(!showActions)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? FlowTheme.cream : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture(perform: onSelect)
            .contextMenu {
                Button("Copy", action: onCopy)
                Button("Delete", role: .destructive, action: onDelete)
            }

            if showDivider {
                Rectangle()
                    .fill(FlowTheme.hairline)
                    .frame(height: 1)
            }
        }
    }

    private var appBadge: some View {
        HStack(spacing: 6) {
            if let icon = AppIconCache.icon(bundleID: entry.appBundleID, appName: entry.appName) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .cornerRadius(3)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FlowTheme.muted)
                    .frame(width: 16, height: 16)
            }

            Text(appLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FlowTheme.muted)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: 88, alignment: .leading)
        .help(entry.appName ?? "Unknown app")
    }

    private func rowIconButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FlowTheme.muted)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Meeting preview / detail

private struct MeetingPreviewCard: View {
    let noteID: MeetingNote.ID
    @Bindable var model: AppModel
    @State private var showFull = false
    @State private var showRemindersExport = false

    private var note: MeetingNote? {
        model.meetings.notes.first(where: { $0.id == noteID })
    }

    private var metaLine: String {
        guard let note else { return "" }
        var parts: [String] = []
        if Calendar.current.isDateInToday(note.createdAt) {
            parts.append("Today · \(note.createdAt.formatted(date: .omitted, time: .shortened).lowercased())")
        } else {
            parts.append(note.createdAt.formatted(date: .abbreviated, time: .shortened))
        }
        if let duration = note.formattedDuration {
            parts.append(duration)
        }
        if note.wordCount > 0 {
            parts.append(note.formattedWordCount)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Group {
            if let note {
                previewBody(note)
            } else {
                Text("Note unavailable")
                    .foregroundStyle(FlowTheme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func previewBody(_ note: MeetingNote) -> some View {
        let keyPoints = note.decisions
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(note.title)
                        .font(.system(size: 26, weight: .regular, design: .serif))
                        .foregroundStyle(FlowTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(metaLine)
                        .font(.system(size: 12))
                        .foregroundStyle(FlowTheme.muted)

                    if !note.attendees.isEmpty {
                        Text(note.attendees.joined(separator: " · "))
                            .font(.system(size: 12))
                            .foregroundStyle(FlowTheme.muted)
                            .lineLimit(3)
                    }

                    MeetingProcessingBanner(note: note) {
                        model.reprocessMeeting(id: note.id)
                    }

                    HStack(spacing: 8) {
                        Button {
                            showFull = true
                        } label: {
                            Text("Open Note")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(FlowTheme.ink)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(FlowTheme.card, in: Capsule())
                                .overlay(Capsule().stroke(FlowTheme.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        if !note.actionItems.isEmpty {
                            Button {
                                showRemindersExport = true
                            } label: {
                                Label("Reminders", systemImage: "checklist")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(FlowTheme.ink)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(FlowTheme.card, in: Capsule())
                                    .overlay(Capsule().stroke(FlowTheme.hairline, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .help("Send action items to a Reminders list")
                        }
                    }

                    if !note.actionItems.isEmpty {
                        previewBulletSection(
                            title: "Action items",
                            icon: "checklist",
                            items: note.actionItems,
                            limit: 5
                        )
                    }

                    if !keyPoints.isEmpty {
                        previewBulletSection(
                            title: "Key points",
                            icon: "lightbulb",
                            items: keyPoints,
                            limit: 5
                        )
                    }

                    if !note.openQuestions.isEmpty {
                        previewBulletSection(
                            title: "Open questions",
                            icon: "questionmark.circle",
                            items: note.openQuestions,
                            limit: 3
                        )
                    }

                    if let brief = note.brief, !brief.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Brief")
                                .font(.system(size: 13, weight: .semibold))
                            Text(brief)
                                .font(.system(size: 13))
                                .foregroundStyle(FlowTheme.ink.opacity(0.85))
                                .lineLimit(5)
                                .textSelection(.enabled)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Overview")
                            .font(.system(size: 13, weight: .semibold))
                        Text(overviewText(for: note))
                            .font(.system(size: 13))
                            .foregroundStyle(FlowTheme.ink.opacity(0.85))
                            .lineLimit(note.actionItems.isEmpty && keyPoints.isEmpty ? 12 : 6)
                            .textSelection(.enabled)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FlowTheme.cream, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .sheet(isPresented: $showFull) {
            MeetingDetailView(noteID: noteID, model: model)
                .frame(minWidth: 640, minHeight: 520)
        }
        .sheet(isPresented: $showRemindersExport) {
            SendActionItemsToRemindersSheet(note: note, reminders: model.reminders)
        }
    }

    private func overviewText(for note: MeetingNote) -> String {
        if note.processingState == .processing {
            return note.processingMessage ?? "Generating overview…"
        }
        if note.summary.isEmpty {
            return "No summary yet."
        }
        return note.summary
    }

    private func previewBulletSection(
        title: String,
        icon: String,
        items: [String],
        limit: Int
    ) -> some View {
        let visible = Array(items.prefix(limit))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FlowTheme.muted)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                Text("\(items.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FlowTheme.ink.opacity(0.7))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(FlowTheme.accentSoft, in: Capsule())
            }

            ForEach(Array(visible.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(FlowTheme.muted.opacity(0.55))
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)
                    Text(item)
                        .font(.system(size: 13))
                        .foregroundStyle(FlowTheme.ink.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }

            if items.count > limit {
                Text("+\(items.count - limit) more in note")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FlowTheme.muted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FlowTheme.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(FlowTheme.hairline, lineWidth: 1)
        )
    }
}

private struct MeetingProcessingBanner: View {
    let note: MeetingNote
    var onReprocess: (() -> Void)?

    var body: some View {
        switch note.processingState {
        case .processing:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Processing notes…")
                        .font(.system(size: 12, weight: .semibold))
                    Text(note.processingMessage ?? "Summary and action items usually finish within a minute for long meetings.")
                        .font(.system(size: 11))
                        .foregroundStyle(FlowTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(FlowTheme.accentSoft.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

        case .incomplete:
            VStack(alignment: .leading, spacing: 8) {
                Text("Summary incomplete")
                    .font(.system(size: 12, weight: .semibold))
                Text(note.processingMessage ?? "Apple Intelligence couldn't fully process this meeting.")
                    .font(.system(size: 11))
                    .foregroundStyle(FlowTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let onReprocess {
                    Button("Retry processing") {
                        onReprocess()
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.bordered)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

        case .complete:
            if let message = note.processingMessage, !message.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 12))
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(FlowTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FlowTheme.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                EmptyView()
            }

        case .idle:
            // Legacy notes with empty structured fields — offer retry.
            if note.endedAt != nil,
               note.actionItems.isEmpty,
               note.decisions.isEmpty,
               note.wordCount > 200
            {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes may need processing")
                        .font(.system(size: 12, weight: .semibold))
                    Text("This long transcript doesn’t have action items yet. Run Apple Intelligence to generate an overview.")
                        .font(.system(size: 11))
                        .foregroundStyle(FlowTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let onReprocess {
                        Button("Generate summary & actions") {
                            onReprocess()
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .buttonStyle(.bordered)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FlowTheme.accentSoft.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                EmptyView()
            }
        }
    }
}

struct MeetingDetailView: View {
    let noteID: MeetingNote.ID
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showRemindersExport = false

    private var note: MeetingNote? {
        model.meetings.notes.first(where: { $0.id == noteID })
    }

    var body: some View {
        Group {
            if let note {
                detailBody(note)
            } else {
                Text("Note unavailable")
                    .padding()
            }
        }
    }

    @ViewBuilder
    private func detailBody(_ note: MeetingNote) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FlowTheme.muted)
                        .frame(width: 28, height: 28)
                        .background(FlowTheme.card, in: Circle())
                        .overlay(Circle().stroke(FlowTheme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Close")
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title)
                            .font(.system(size: 28, weight: .regular, design: .serif))
                        Text(note.createdAt.formatted(date: .complete, time: .shortened))
                            .foregroundStyle(FlowTheme.muted)
                        if !note.attendees.isEmpty {
                            Text(note.attendees.joined(separator: ", "))
                                .foregroundStyle(FlowTheme.muted)
                        }
                    }

                    MeetingProcessingBanner(note: note) {
                        model.reprocessMeeting(id: note.id)
                    }

                    if let brief = note.brief, !brief.isEmpty {
                        section("Pre-meeting brief", brief)
                    }

                    section(
                        "Overview",
                        note.processingState == .processing
                            ? (note.processingMessage ?? "Generating overview…")
                            : (note.summary.isEmpty ? "No summary yet." : note.summary)
                    )

                    if !note.actionItems.isEmpty {
                        bulletSection("Action items", note.actionItems)
                    }
                    if !note.decisions.isEmpty {
                        bulletSection("Key points", note.decisions)
                    }
                    if !note.openQuestions.isEmpty {
                        bulletSection("Open questions", note.openQuestions)
                    }
                    if let catchUp = note.catchUp, !catchUp.isEmpty {
                        section("Catch-up", catchUp)
                    }

                    if !note.segments.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Transcript")
                                .font(.title3.weight(.semibold))
                            ForEach(note.segments.sorted(by: { $0.startOffset < $1.startOffset })) { seg in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(seg.speaker)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(FlowTheme.muted)
                                        .frame(width: 64, alignment: .leading)
                                    Text(seg.text)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    } else {
                        section("Transcript", note.transcript.isEmpty ? "Empty transcript." : note.transcript)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
                .frame(maxWidth: 720, alignment: .leading)
            }

            HStack {
                Button("Copy Markdown") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(note.markdownExport, forType: .string)
                }
                Button("Export…") { exportMarkdown(note) }
                if !note.actionItems.isEmpty {
                    Button("Send to Reminders…") {
                        showRemindersExport = true
                    }
                }
                if note.processingState != .processing {
                    Button("Reprocess") {
                        model.reprocessMeeting(id: note.id)
                    }
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(FlowTheme.cream.opacity(0.9))
        }
        .background(FlowTheme.cream)
        .sheet(isPresented: $showRemindersExport) {
            SendActionItemsToRemindersSheet(note: note, reminders: model.reminders)
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
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                    Text(item)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func exportMarkdown(_ note: MeetingNote) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.text]
        panel.nameFieldStringValue = "\(note.title).md"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? note.markdownExport.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

private struct SendActionItemsToRemindersSheet: View {
    let note: MeetingNote
    @Bindable var reminders: RemindersService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedListID: String?
    @State private var statusMessage: String?
    @State private var isBusy = false
    @State private var didSucceed = false

    private var itemCount: Int { note.actionItems.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Send to Reminders")
                .font(.system(size: 20, weight: .semibold))

            Text("Add \(itemCount) action item\(itemCount == 1 ? "" : "s") from “\(note.title)” to a list.")
                .font(.system(size: 13))
                .foregroundStyle(FlowTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if !reminders.isAuthorized {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Fn Dictate needs access to Reminders.")
                        .font(.system(size: 13))
                    Button("Allow Reminders Access") {
                        Task {
                            let granted = await reminders.requestAccess()
                            if granted {
                                selectedListID = reminders.resolvedListID()
                                statusMessage = nil
                            } else {
                                statusMessage = RemindersServiceError.notAuthorized.localizedDescription
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            } else if reminders.lists.isEmpty {
                Text(RemindersServiceError.noWritableLists.localizedDescription)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            } else {
                Picker("List", selection: Binding(
                    get: { selectedListID ?? reminders.resolvedListID() ?? "" },
                    set: { selectedListID = $0 }
                )) {
                    ForEach(reminders.lists) { list in
                        Text(list.title).tag(list.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(note.actionItems.prefix(6).enumerated()), id: \.offset) { _, item in
                        Text("• \(item)")
                            .font(.system(size: 12))
                            .foregroundStyle(FlowTheme.ink.opacity(0.85))
                            .lineLimit(2)
                    }
                    if note.actionItems.count > 6 {
                        Text("+\(note.actionItems.count - 6) more")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(FlowTheme.muted)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FlowTheme.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(FlowTheme.hairline, lineWidth: 1)
                )
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(didSucceed ? .green : .red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if reminders.isAuthorized, !reminders.lists.isEmpty {
                    Button(didSucceed ? "Done" : "Add to Reminders") {
                        if didSucceed {
                            dismiss()
                        } else {
                            send()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isBusy || (selectedListID ?? reminders.resolvedListID()) == nil)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(FlowTheme.cream)
        .task {
            reminders.refreshStatus()
            if reminders.isAuthorized {
                reminders.reloadLists()
                selectedListID = reminders.resolvedListID()
            } else {
                let granted = await reminders.requestAccess()
                if granted {
                    selectedListID = reminders.resolvedListID()
                }
            }
        }
    }

    private func send() {
        guard let listID = selectedListID ?? reminders.resolvedListID() else { return }
        isBusy = true
        statusMessage = nil
        defer { isBusy = false }
        do {
            let count = try reminders.addActionItems(
                note.actionItems,
                toListID: listID,
                meetingTitle: note.title
            )
            let listTitle = reminders.lists.first(where: { $0.id == listID })?.title ?? "Reminders"
            didSucceed = true
            statusMessage = "Added \(count) reminder\(count == 1 ? "" : "s") to \(listTitle)."
        } catch {
            didSucceed = false
            statusMessage = error.localizedDescription
        }
    }
}
