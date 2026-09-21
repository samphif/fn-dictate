import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var openMeetingDetail: MeetingDetailPresentation?
    @State private var showProjectsEditor = false
    @State private var meetingProjectFilter: MeetingProject.ID?
    @AppStorage("meetingPreviewRailWidth") private var meetingPreviewRailWidth = 440.0
    /// Live width while dragging. Persisted to `meetingPreviewRailWidth` only on release
    /// so UserDefaults writes don't reset the gesture mid-drag.
    @State private var meetingPreviewDragWidth: Double?
    @State private var meetingPreviewDragStartWidth: Double?
    @State private var meetingPreviewDragOriginX: CGFloat?

    private struct MeetingDetailPresentation: Identifiable {
        let id: MeetingNote.ID
    }

    enum LibrarySection: String, CaseIterable, Identifiable {
        case dictations
        case insights
        case dictionary
        case meetings
        case formatting

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .dictations: return "mic"
            case .insights: return "chart.bar"
            case .dictionary: return "textformat"
            case .meetings: return "doc.text"
            case .formatting: return "slider.horizontal.3"
            }
        }

        var help: String {
            switch self {
            case .dictations: return "Dictations"
            case .insights: return "Insights"
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
        .sheet(item: $openMeetingDetail) { presentation in
            MeetingDetailView(noteID: presentation.id, model: model)
                .frame(minWidth: 960, idealWidth: 1180, minHeight: 720, idealHeight: 900)
                .presentationSizing(.page)
        }
        .sheet(isPresented: $showProjectsEditor) {
            ProjectsEditorSheet(model: model)
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
        case .insights:
            InsightsView(
                insights: UsageInsights.from(
                    entries: model.history.entries,
                    dictionary: model.dictionary.entries
                )
            )
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
        case .insights: section = .insights
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

    private var usageInsights: UsageInsights {
        UsageInsights.from(entries: model.history.entries, dictionary: model.dictionary.entries)
    }

    private var statsCard: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                section = .insights
            }
        } label: {
            VStack(alignment: .leading, spacing: 18) {
                statRow(value: usageInsights.formattedWordCount, label: "total words")
                statRow(value: "\(usageInsights.dictationCount)", label: "dictations")
                statRow(
                    value: "\(usageInsights.currentStreak)",
                    label: "day streak"
                )
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FlowTheme.cream, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Open Insights")
        .accessibilityLabel("Insights, \(usageInsights.formattedWordCount) total words, \(usageInsights.currentStreak) day streak")
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

            if let raw = entry.originalText?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty
            {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Raw speech")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FlowTheme.muted)
                        .tracking(0.4)

                    Text(raw)
                        .font(.system(size: 13))
                        .foregroundStyle(FlowTheme.ink.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .frame(minHeight: 56, maxHeight: 120, alignment: .topLeading)
                        .background(FlowTheme.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(FlowTheme.hairline, lineWidth: 1)
                        )
                        .textSelection(.enabled)
                }
            }

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
                Text("Text · pasted")
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
            .frame(maxWidth: .infinity, alignment: .center)
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
                         ? "Add names and jargon, or fix a misspelling after paste with Learn from in-app corrections on."
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
                    if entry.isStarred {
                        Text("✨")
                            .font(.system(size: 11))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(entry.incorrect) goes to \(entry.correct)")
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
                        TextField("Heard / incorrect", text: $editIncorrect)
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
            Text("Map what speech recognition hears to the spelling you want.")
                .foregroundStyle(FlowTheme.muted)

            Form {
                TextField("Heard / incorrect", text: $newIncorrect)
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
                .disabled(
                    newIncorrect.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || newCorrect.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func canSaveDictionaryEdit(_ entry: DictionaryEntry) -> Bool {
        let incorrect = editIncorrect.trimmingCharacters(in: .whitespacesAndNewlines)
        let correct = editCorrect.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incorrect.isEmpty, !correct.isEmpty else { return false }
        guard incorrect.caseInsensitiveCompare(correct) != .orderedSame else { return false }
        return incorrect != entry.incorrect || correct != entry.correct
    }

    private func saveDictionaryEdit(_ entry: DictionaryEntry) {
        let incorrect = editIncorrect.trimmingCharacters(in: .whitespacesAndNewlines)
        let correct = editCorrect.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSaveDictionaryEdit(entry) else { return }
        var updated = entry
        updated.incorrect = incorrect
        updated.correct = correct
        model.dictionary.update(updated)
        flash("Saved")
    }

    // MARK: - Meetings

    private var filteredMeetings: [MeetingNote] {
        let q = meetingSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let searched: [MeetingNote]
        if q.isEmpty {
            searched = model.meetings.notes
        } else {
            searched = model.meetings.notes.filter {
                $0.title.localizedCaseInsensitiveContains(q)
                    || $0.summary.localizedCaseInsensitiveContains(q)
                    || $0.transcript.localizedCaseInsensitiveContains(q)
                    || ($0.sourceDisplayLabel?.localizedCaseInsensitiveContains(q) ?? false)
                    || ($0.sourceAppName?.localizedCaseInsensitiveContains(q) ?? false)
                    || (model.project(for: $0)?.name.localizedCaseInsensitiveContains(q) ?? false)
            }
        }
        guard let meetingProjectFilter else { return searched }
        return searched.filter { $0.projectID == meetingProjectFilter }
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

                        Button {
                            showProjectsEditor = true
                        } label: {
                            Label("Projects", systemImage: "tag")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.borderless)
                        .help("Tag notes by project and set each project’s icon")
                    }
                    .padding(.top, 4)

                    if !model.projects.projects.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                projectFilterChip(title: "All", project: nil, selected: meetingProjectFilter == nil) {
                                    meetingProjectFilter = nil
                                }
                                ForEach(model.projects.projects) { project in
                                    projectFilterChip(
                                        title: project.name,
                                        project: project,
                                        selected: meetingProjectFilter == project.id
                                    ) {
                                        meetingProjectFilter = meetingProjectFilter == project.id ? nil : project.id
                                    }
                                }
                            }
                        }
                    }

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

            meetingPreviewResizeHandle

            meetingPreviewRail
                .padding([.top, .trailing, .bottom], 20)
        }
    }

    private var meetingPreviewMinWidth: Double { 300 }
    private var meetingPreviewMaxWidth: Double { 820 }

    private var meetingPreviewDisplayedWidth: Double {
        let raw = meetingPreviewDragWidth ?? meetingPreviewRailWidth
        return min(max(raw, meetingPreviewMinWidth), meetingPreviewMaxWidth)
    }

    private var meetingPreviewResizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 10)
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: 1)
                    .fill(FlowTheme.hairline)
                    .frame(width: 1, height: 48)
            }
            .help("Drag to resize preview")
            .onHover { hovering in
                DispatchQueue.main.async {
                    if hovering {
                        NSCursor.resizeLeftRight.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if meetingPreviewDragOriginX == nil {
                            meetingPreviewDragOriginX = value.startLocation.x
                            meetingPreviewDragStartWidth = meetingPreviewRailWidth
                        }
                        let origin = meetingPreviewDragOriginX ?? value.startLocation.x
                        let start = meetingPreviewDragStartWidth ?? meetingPreviewRailWidth
                        let proposed = start - Double(value.location.x - origin)
                        let clamped = min(max(proposed, meetingPreviewMinWidth), meetingPreviewMaxWidth)
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            meetingPreviewDragWidth = clamped
                        }
                    }
                    .onEnded { value in
                        let origin = meetingPreviewDragOriginX ?? value.startLocation.x
                        let start = meetingPreviewDragStartWidth ?? meetingPreviewRailWidth
                        let proposed = start - Double(value.location.x - origin)
                        meetingPreviewRailWidth = min(
                            max(proposed, meetingPreviewMinWidth),
                            meetingPreviewMaxWidth
                        )
                        meetingPreviewDragWidth = nil
                        meetingPreviewDragStartWidth = nil
                        meetingPreviewDragOriginX = nil
                    }
            )
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
                    Button(model.calendar.needsOpenSettings ? "Open Calendar Settings" : "Connect Calendar") {
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
            model.calendar.refreshStatus()
            model.refreshUpcomingCalendar()
            Task { await model.refreshUpcomingBriefIfNeeded() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // User may have flipped Calendars in System Settings while the app was in back.
            model.calendar.refreshStatus()
            model.refreshUpcomingCalendar()
            if model.calendar.isAuthorized {
                Task { await model.refreshUpcomingBriefIfNeeded() }
            }
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

            if model.phase == .meetingRecording {
                HStack(spacing: 8) {
                    liveChannelBadge(
                        title: "You",
                        hot: model.activeMeetingChannel == .you,
                        level: model.audioLevel
                    )
                    liveChannelBadge(
                        title: model.remoteSpeakerLabel,
                        hot: model.activeMeetingChannel == .others,
                        level: model.remoteAudioLevel
                    )
                    if liveNote?.systemAudioCaptureFailed == true {
                        Text("System audio failed — others may show as You")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                    Spacer(minLength: 0)
                }

                if !model.liveParticipantRoster.isEmpty {
                    Text("Roster: \(model.liveParticipantRoster.prefix(8).joined(separator: ", "))")
                        .font(.system(size: 11))
                        .foregroundStyle(FlowTheme.muted)
                        .lineLimit(2)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let liveNote, !liveNote.segments.isEmpty {
                        ForEach(liveNote.segments.sorted(by: { $0.startOffset < $1.startOffset })) { seg in
                            HStack(alignment: .top, spacing: 8) {
                                VoiceSpeakerLabel(
                                    speaker: seg.speaker,
                                    voiceID: seg.voiceID,
                                    fontSize: 11,
                                    width: 92
                                ) { id, name in
                                    model.renameRememberedVoice(id: id, to: name)
                                }
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

    private func liveChannelBadge(title: String, hot: Bool, level: Float) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(hot ? FlowTheme.solid : FlowTheme.muted.opacity(0.35))
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hot ? FlowTheme.ink : FlowTheme.muted)
            Text(String(format: "%.0f%%", Double(min(1, level)) * 100))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(FlowTheme.muted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hot ? FlowTheme.solid.opacity(0.12) : FlowTheme.cream.opacity(0.7))
        )
    }

    private func speakerColor(_ speaker: String) -> Color {
        if speaker == "You" { return FlowTheme.ink }
        if speaker == "Others" { return FlowTheme.muted }
        return FlowTheme.solid
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
            if let source = model.callSourceLabel(for: note) {
                parts.append(source)
            }
            if let duration = note.formattedDuration {
                parts.append(duration)
            }
            if note.wordCount > 0 {
                parts.append(note.formattedWordCount)
            }
            return parts
        }()
        let project = model.project(for: note)
        let actionPreview = note.actionItems.first.map { ParsedActionItem.parse($0) }
        let actionLine: String? = actionPreview.map { parsed in
            let task = parsed.task.isEmpty ? (note.actionItems.first ?? "") : parsed.task
            if let assignee = parsed.assignee {
                return "[\(assignee)] \(task)"
            }
            return task
        }

        return HStack(alignment: .top, spacing: 12) {
            meetingSourceIcon(note, project: project)

            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FlowTheme.ink)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let project {
                        Text(project.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ProjectMark.color(hex: project.colorHex))
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                ProjectMark.color(hex: project.colorHex).opacity(0.16),
                                in: Capsule()
                            )
                    }
                    Text(metaParts.joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundStyle(FlowTheme.muted)
                        .lineLimit(1)
                }

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
                        Text(actionLine ?? "")
                            .font(.system(size: 12))
                            .foregroundStyle(FlowTheme.ink.opacity(actionPreview.isDone ? 0.45 : 0.82))
                            .strikethrough(actionPreview.isDone, color: FlowTheme.muted)
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
                            ? "1 action item: \(actionPreview.task)"
                            : "\(note.actionItems.count) action items. First: \(actionPreview.task)"
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
        .gesture(
            TapGesture(count: 2)
                .onEnded { _ in openMeeting(note) }
                .exclusively(before:
                    TapGesture(count: 1)
                        .onEnded { _ in selectedMeetingID = note.id }
                )
        )
        .contextMenu {
            Button("Open Note") {
                openMeeting(note)
            }
            Menu("Project") {
                Button("None") {
                    model.setMeetingProject(nil, noteID: note.id)
                }
                ForEach(model.projects.projects) { project in
                    Button {
                        model.setMeetingProject(project.id, noteID: note.id)
                    } label: {
                        if note.projectID == project.id {
                            Label(project.name, systemImage: "checkmark")
                        } else {
                            Text(project.name)
                        }
                    }
                }
                Divider()
                Button("Edit projects…") {
                    showProjectsEditor = true
                }
            }
            if note.processingState == .processing {
                Button("Stop Processing") {
                    model.stopMeetingProcessing(id: note.id)
                }
                Button("Retry Processing") {
                    model.reprocessMeeting(id: note.id)
                }
            }
            Button("Copy Markdown") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.markdownExport(for: note), forType: .string)
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
                if openMeetingDetail?.id == note.id { openMeetingDetail = nil }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Selects the note. Double-click to open the full note.")
        .accessibilityAction(named: "Open Note") {
            openMeeting(note)
        }
    }

    private func openMeeting(_ note: MeetingNote) {
        selectedMeetingID = note.id
        openMeetingDetail = MeetingDetailPresentation(id: note.id)
    }

    @ViewBuilder
    private func meetingSourceIcon(_ note: MeetingNote, project: MeetingProject?) -> some View {
        Group {
            if let project {
                ProjectMark(
                    project: project,
                    image: model.projects.iconImage(for: project),
                    size: 34
                )
            } else if let icon = AppIconCache.icon(
                bundleID: note.sourceAppBundleID,
                appName: note.sourceAppName
            ) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)
                    .frame(width: 34, height: 34)
                    .background(FlowTheme.cream, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: "doc.text")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FlowTheme.muted)
                    .frame(width: 34, height: 34)
                    .background(FlowTheme.cream, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .help(project.map { "\($0.name)\(model.callSourceLabel(for: note).map { " · \($0)" } ?? "")" } ?? (note.sourceDisplayLabel ?? "Meeting note"))
    }

    private func projectFilterChip(
        title: String,
        project: MeetingProject?,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let project {
                    Circle()
                        .fill(ProjectMark.color(hex: project.colorHex))
                        .frame(width: 7, height: 7)
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(selected ? FlowTheme.ink : FlowTheme.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(selected ? FlowTheme.card : Color.clear)
            )
            .overlay(Capsule().stroke(FlowTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
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
        let width = meetingPreviewDisplayedWidth
        if let id = selectedMeetingID,
           let note = model.meetings.notes.first(where: { $0.id == id })
        {
            MeetingPreviewCard(noteID: note.id, model: model)
                .frame(width: width)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(FlowTheme.muted)
                Text("Select a note")
                    .font(.subheadline)
                    .foregroundStyle(FlowTheme.muted)
            }
            .frame(width: width)
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
enum AppIconCache {
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

private enum MeetingRailSection: String, Identifiable {
    case actionItems
    case keyPoints

    var id: String { rawValue }

    var title: String {
        switch self {
        case .actionItems: "Action items"
        case .keyPoints: "Key points"
        }
    }

    var icon: String {
        switch self {
        case .actionItems: "checklist"
        case .keyPoints: "lightbulb"
        }
    }
}

private struct MeetingPreviewCard: View {
    let noteID: MeetingNote.ID
    @Bindable var model: AppModel
    @State private var showFull = false
    @State private var showRemindersExport = false
    @State private var focusedSection: MeetingRailSection?

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
        if let project = model.project(for: note) {
            parts.append(project.name)
        }
        if let source = model.callSourceLabel(for: note) {
            parts.append(source)
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

                    MeetingProcessingBanner(
                        note: note,
                        onReprocess: { model.reprocessMeeting(id: note.id) },
                        onStop: { model.stopMeetingProcessing(id: note.id) }
                    )

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
                        previewActionItemsSection(note.actionItems, limit: 6) {
                            focusedSection = .actionItems
                        }
                    }

                    if !keyPoints.isEmpty {
                        previewBulletSection(
                            title: "Key points",
                            icon: "lightbulb",
                            items: keyPoints,
                            limit: 5
                        ) {
                            focusedSection = .keyPoints
                        }
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
                .frame(minWidth: 960, idealWidth: 1180, minHeight: 720, idealHeight: 900)
                .presentationSizing(.page)
        }
        .sheet(isPresented: $showRemindersExport) {
            SendActionItemsToRemindersSheet(note: note, reminders: model.reminders)
        }
        .sheet(item: $focusedSection) { section in
            MeetingSectionSheet(noteID: noteID, section: section, model: model)
                .frame(minWidth: 480, idealWidth: 560, maxWidth: 680, minHeight: 420, idealHeight: 640)
                .presentationSizing(.fitted)
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

    private func previewActionItemsSection(
        _ items: [String],
        limit: Int,
        onOpen: @escaping () -> Void
    ) -> some View {
        let groups = ActionItemGroup.groups(from: items)
        var remaining = limit
        var visible: [(group: ActionItemGroup, tasks: [(text: String, done: Bool)])] = []
        for group in groups {
            guard remaining > 0 else { break }
            let tasks = group.indices.compactMap { index -> (text: String, done: Bool)? in
                guard items.indices.contains(index) else { return nil }
                let parsed = ParsedActionItem.parse(items[index])
                let text = parsed.task.isEmpty ? items[index] : parsed.task
                return (text, parsed.isDone)
            }
            let slice = Array(tasks.prefix(remaining))
            remaining -= slice.count
            visible.append((group, slice))
        }

        return VStack(alignment: .leading, spacing: 10) {
            previewSectionHeader(
                title: "Action items",
                icon: "checklist",
                count: items.count,
                help: "Open all action items",
                action: onOpen
            )

            ForEach(Array(visible.enumerated()), id: \.offset) { _, entry in
                let style = AssigneePersona.style(for: entry.group.assignee)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: style.icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(style.tint)
                        Text(entry.group.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(FlowTheme.ink.opacity(0.9))
                        Text("\(entry.group.count)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(style.tint.opacity(0.9))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(style.soft, in: Capsule())
                    }

                    ForEach(Array(entry.tasks.enumerated()), id: \.offset) { _, task in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(style.tint.opacity(task.done ? 0.9 : 0.55))
                                .padding(.top, 2)
                            Text(task.text)
                                .font(.system(size: 13))
                                .foregroundStyle(FlowTheme.ink.opacity(task.done ? 0.45 : 0.9))
                                .strikethrough(task.done, color: FlowTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if items.count > limit {
                previewMoreButton(hiddenCount: items.count - limit, action: onOpen)
            }
        }
        .padding(12)
        .background(FlowTheme.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(FlowTheme.hairline, lineWidth: 1)
        )
    }

    private func previewBulletSection(
        title: String,
        icon: String,
        items: [String],
        limit: Int,
        onOpen: (() -> Void)? = nil
    ) -> some View {
        let visible = Array(items.prefix(limit))
        return VStack(alignment: .leading, spacing: 8) {
            if let onOpen {
                previewSectionHeader(
                    title: title,
                    icon: icon,
                    count: items.count,
                    help: "Open all \(title.lowercased())",
                    action: onOpen
                )
            } else {
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

            if items.count > limit, let onOpen {
                previewMoreButton(hiddenCount: items.count - limit, action: onOpen)
            } else if items.count > limit {
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

    private func previewSectionHeader(
        title: String,
        icon: String,
        count: Int,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FlowTheme.muted)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FlowTheme.ink)
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FlowTheme.ink.opacity(0.7))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(FlowTheme.accentSoft, in: Capsule())
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(FlowTheme.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func previewMoreButton(hiddenCount: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("+\(hiddenCount) more")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FlowTheme.ink.opacity(0.75))
        }
        .buttonStyle(.plain)
        .help("Open the full list")
    }
}

private struct MeetingSectionSheet: View {
    let noteID: MeetingNote.ID
    let section: MeetingRailSection
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showRemindersExport = false

    private var note: MeetingNote? {
        model.meetings.notes.first(where: { $0.id == noteID })
    }

    var body: some View {
        Group {
            if let note {
                sheetBody(note)
            } else {
                Text("Note unavailable")
                    .foregroundStyle(FlowTheme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(FlowTheme.cream)
    }

    @ViewBuilder
    private func sheetBody(_ note: MeetingNote) -> some View {
        let items = section == .actionItems ? note.actionItems : note.decisions
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FlowTheme.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.system(size: 18, weight: .semibold))
                    Text(note.title)
                        .font(.system(size: 12))
                        .foregroundStyle(FlowTheme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("\(items.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FlowTheme.ink.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(FlowTheme.accentSoft, in: Capsule())
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
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch section {
                    case .actionItems:
                        actionItemsList(note)
                    case .keyPoints:
                        keyPointsList(note.decisions)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if section == .actionItems, !note.actionItems.isEmpty {
                HStack {
                    Button("Send to Reminders…") {
                        showRemindersExport = true
                    }
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(FlowTheme.cream.opacity(0.9))
            }
        }
        .sheet(isPresented: $showRemindersExport) {
            SendActionItemsToRemindersSheet(note: note, reminders: model.reminders)
        }
    }

    private func actionItemsList(_ note: MeetingNote) -> some View {
        let groups = ActionItemGroup.groups(from: note.actionItems)
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(groups) { group in
                ActionItemGroupCard(
                    group: group,
                    rawItems: note.actionItems,
                    candidates: assigneeOptions(for: note, including: group.assignee)
                ) { index, updated in
                    model.meetings.updateActionItem(id: note.id, index: index, text: updated)
                }
            }
        }
    }

    private func keyPointsList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(FlowTheme.muted.opacity(0.55))
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)
                    Text(item)
                        .font(.system(size: 14))
                        .foregroundStyle(FlowTheme.ink.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func assigneeOptions(for note: MeetingNote, including current: String?) -> [String] {
        var options = note.actionItemAssigneeCandidates(including: model.project(for: note)?.people ?? [])
        if let current, !current.isEmpty,
           !options.contains(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) {
            options.append(current)
        }
        for raw in note.actionItems {
            if let name = ParsedActionItem.parse(raw).assignee,
               !options.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                options.append(name)
            }
        }
        return options
    }
}

private struct MeetingProcessingBanner: View {
    let note: MeetingNote
    var onReprocess: (() -> Void)?
    var onStop: (() -> Void)?

    var body: some View {
        switch note.processingState {
        case .processing:
            VStack(alignment: .leading, spacing: 8) {
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
                HStack(spacing: 8) {
                    if let onStop {
                        Button("Stop") {
                            onStop()
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .buttonStyle(.bordered)
                    }
                    if let onReprocess {
                        Button("Retry") {
                            onReprocess()
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
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
    @State private var renameFrom: String = ""
    @State private var renameTo: String = ""
    @State private var showRenameSheet = false
    @State private var overviewExpanded = false

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
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title)
                            .font(.system(size: 28, weight: .regular, design: .serif))
                        Text(note.createdAt.formatted(date: .complete, time: .shortened))
                            .foregroundStyle(FlowTheme.muted)
                        if let project = model.project(for: note) {
                            HStack(spacing: 8) {
                                ProjectMark(
                                    project: project,
                                    image: model.projects.iconImage(for: project),
                                    size: 16
                                )
                                Text(project.name)
                                    .foregroundStyle(FlowTheme.muted)
                            }
                        }
                        if let source = model.callSourceLabel(for: note) {
                            HStack(spacing: 8) {
                                if note.sourceAppBundleID != nil || note.sourceAppName != nil,
                                   let icon = AppIconCache.icon(
                                    bundleID: note.sourceAppBundleID,
                                    appName: note.sourceAppName
                                   ) {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .interpolation(.high)
                                        .frame(width: 14, height: 14)
                                }
                                Text(source)
                                    .foregroundStyle(FlowTheme.muted)
                            }
                        }
                        if !note.attendees.isEmpty {
                            Text(note.attendees.joined(separator: ", "))
                                .foregroundStyle(FlowTheme.muted)
                        }
                        if !note.participantRoster.isEmpty {
                            Text("Roster: \(note.participantRoster.joined(separator: ", "))")
                                .font(.system(size: 12))
                                .foregroundStyle(FlowTheme.muted)
                        }
                    }

                    MeetingProcessingBanner(
                        note: note,
                        onReprocess: { model.reprocessMeeting(id: note.id) },
                        onStop: { model.stopMeetingProcessing(id: note.id) }
                    )

                    if let brief = note.brief, !brief.isEmpty {
                        section("Pre-meeting brief", brief)
                    }

                    if !note.actionItems.isEmpty {
                        actionItemsSection(note)
                    }

                    overviewSection(note)

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
                            HStack {
                                Text("Transcript")
                                    .font(.title3.weight(.semibold))
                                Spacer()
                                Button("Rename speaker…") {
                                    renameFrom = uniqueSpeakers(in: note).first(where: { $0 != "You" })
                                        ?? uniqueSpeakers(in: note).first
                                        ?? "Others"
                                    renameTo = ""
                                    showRenameSheet = true
                                }
                                .font(.system(size: 12, weight: .medium))
                            }
                            if note.segments.contains(where: { $0.speaker.caseInsensitiveCompare("You") != .orderedSame }) {
                                Text("Each other person is kept as their own voice. Click a name to remember them in later meetings.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(FlowTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            ForEach(note.segments.sorted(by: { $0.startOffset < $1.startOffset })) { seg in
                                HStack(alignment: .top, spacing: 10) {
                                    VoiceSpeakerLabel(
                                        speaker: seg.speaker,
                                        voiceID: seg.voiceID,
                                        fontSize: 12,
                                        width: 96
                                    ) { id, name in
                                        model.renameRememberedVoice(id: id, to: name)
                                    }
                                    Text(seg.text)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    } else {
                        section("Transcript", note.transcript.isEmpty ? "Empty transcript." : note.transcript)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Copy Markdown") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.markdownExport(for: note), forType: .string)
                }
                Button("Export…") { exportMarkdown(note) }
                if !note.actionItems.isEmpty {
                    Button("Send to Reminders…") {
                        showRemindersExport = true
                    }
                }
                if note.processingState == .processing {
                    Button("Stop") {
                        model.stopMeetingProcessing(id: note.id)
                    }
                }
                Button(note.processingState == .processing ? "Retry" : "Reprocess") {
                    model.reprocessMeeting(id: note.id)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(FlowTheme.cream.opacity(0.9))
        }
        .background(FlowTheme.cream)
        .sheet(isPresented: $showRemindersExport) {
            SendActionItemsToRemindersSheet(note: note, reminders: model.reminders)
        }
        .sheet(isPresented: $showRenameSheet) {
            RenameSpeakerSheet(
                speakers: uniqueSpeakers(in: note),
                suggestions: renameSuggestions(for: note),
                from: $renameFrom,
                to: $renameTo
            ) {
                model.renameMeetingSpeaker(noteID: note.id, from: renameFrom, to: renameTo)
                showRenameSheet = false
            } onCancel: {
                showRenameSheet = false
            }
        }
    }

    private func uniqueSpeakers(in note: MeetingNote) -> [String] {
        note.segments.map(\.speaker).uniqued()
    }

    private func renameSuggestions(for note: MeetingNote) -> [String] {
        (note.attendees + note.participantRoster + [note.remoteOneOnOneName].compactMap { $0 })
            .uniqued()
    }

    private func overviewSection(_ note: MeetingNote) -> some View {
        let overview: String = {
            if note.processingState == .processing {
                return note.processingMessage ?? "Generating overview…"
            }
            return note.summary.isEmpty ? "No summary yet." : note.summary
        }()
        let canCollapse = overview.count > 180 || overview.contains("\n")

        return VStack(alignment: .leading, spacing: 6) {
            Text("Overview")
                .font(.title3.weight(.semibold))
            Text(overview)
                .font(.system(size: 13))
                .foregroundStyle(FlowTheme.ink.opacity(0.85))
                .lineLimit(overviewExpanded || !canCollapse ? nil : 3)
                .textSelection(.enabled)
            if canCollapse {
                Button(overviewExpanded ? "Show less" : "Show more") {
                    overviewExpanded.toggle()
                }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(FlowTheme.accent)
            }
        }
    }

    private func actionItemsSection(_ note: MeetingNote) -> some View {
        let groups = ActionItemGroup.groups(from: note.actionItems)
        let doneCount = note.actionItems.filter { ParsedActionItem.parse($0).isDone }.count
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("Action items")
                    .font(.title3.weight(.semibold))
                Text("\(note.actionItems.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FlowTheme.ink.opacity(0.7))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(FlowTheme.accentSoft, in: Capsule())
                if doneCount > 0 {
                    Text("\(doneCount) done")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FlowTheme.muted)
                }
                Spacer(minLength: 0)
                Text("by assignee")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FlowTheme.muted)
            }

            ForEach(groups) { group in
                ActionItemGroupCard(
                    group: group,
                    rawItems: note.actionItems,
                    candidates: assigneeOptions(for: note, including: group.assignee)
                ) { index, updated in
                    model.meetings.updateActionItem(id: note.id, index: index, text: updated)
                }
            }
        }
    }

    private func assigneeOptions(for note: MeetingNote, including current: String?) -> [String] {
        var options = note.actionItemAssigneeCandidates(including: model.project(for: note)?.people ?? [])
        if let current, !current.isEmpty,
           !options.contains(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) {
            options.append(current)
        }
        // Preserve ad-hoc labels like "Team" that appear on other items.
        for raw in note.actionItems {
            if let name = ParsedActionItem.parse(raw).assignee,
               !options.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                options.append(name)
            }
        }
        return options
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
            try? model.markdownExport(for: note).write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

private struct RenameSpeakerSheet: View {
    let speakers: [String]
    let suggestions: [String]
    @Binding var from: String
    @Binding var to: String
    let onApply: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename speaker")
                .font(.system(size: 20, weight: .semibold))
            Text("Applies to every matching line in this note. Manual renames are kept when you reprocess.")
                .font(.system(size: 13))
                .foregroundStyle(FlowTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Current label", selection: $from) {
                ForEach(speakers, id: \.self) { name in
                    Text(name).tag(name)
                }
            }

            TextField("New name", text: $to)
                .textFieldStyle(.roundedBorder)

            if !suggestions.isEmpty {
                Text("Suggestions")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FlowTheme.muted)
                FlowLayoutSuggestions(names: suggestions) { name in
                    to = name
                }
            }

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Apply to all") {
                    onApply()
                }
                .disabled(to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct FlowLayoutSuggestions: View {
    let names: [String]
    let onPick: (String) -> Void

    var body: some View {
        // Simple wrapping via flexible stack — keep quiet, no card chrome.
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(names.prefix(12)), id: \.self) { name in
                Button(name) { onPick(name) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FlowTheme.solid)
            }
        }
    }
}

private enum AssigneePersona {
    struct Style {
        let icon: String
        let tint: Color
        let soft: Color
    }

    private static let palette: [(icon: String, red: Double, green: Double, blue: Double)] = [
        ("hare.fill", 0.91, 0.55, 0.38),
        ("bird.fill", 0.42, 0.68, 0.84),
        ("leaf.fill", 0.45, 0.72, 0.48),
        ("flame.fill", 0.93, 0.46, 0.36),
        ("bolt.fill", 0.94, 0.76, 0.30),
        ("fish.fill", 0.38, 0.62, 0.78),
        ("cat.fill", 0.78, 0.52, 0.84),
        ("dog.fill", 0.72, 0.56, 0.40),
        ("tortoise.fill", 0.40, 0.70, 0.56),
        ("sparkles", 0.84, 0.62, 0.90),
        ("moon.stars.fill", 0.55, 0.58, 0.88),
        ("cup.and.saucer.fill", 0.70, 0.52, 0.40),
        ("gamecontroller.fill", 0.48, 0.74, 0.58),
        ("paintbrush.pointed.fill", 0.88, 0.48, 0.62),
        ("carrot.fill", 0.95, 0.58, 0.32),
        ("teddybear.fill", 0.82, 0.60, 0.46)
    ]

    static func style(for assignee: String?) -> Style {
        guard let assignee, !assignee.isEmpty else {
            return Style(
                icon: "person.slash",
                tint: FlowTheme.muted,
                soft: FlowTheme.card.opacity(0.75)
            )
        }

        if assignee.caseInsensitiveCompare("You") == .orderedSame {
            let tint = Color(red: 0.95, green: 0.74, blue: 0.28)
            return Style(icon: "star.fill", tint: tint, soft: tint.opacity(0.20))
        }

        let hash = assignee.lowercased().unicodeScalars.reduce(into: 0) { partial, scalar in
            partial = partial &* 31 &+ Int(scalar.value)
        }
        let entry = palette[abs(hash) % palette.count]
        let tint = Color(red: entry.red, green: entry.green, blue: entry.blue)
        return Style(icon: entry.icon, tint: tint, soft: tint.opacity(0.18))
    }
}

private struct ActionItemGroupCard: View {
    let group: ActionItemGroup
    let rawItems: [String]
    let candidates: [String]
    let onChange: (Int, String) -> Void

    private var style: AssigneePersona.Style { AssigneePersona.style(for: group.assignee) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AssigneeBadge(assignee: group.assignee, style: style)
                Text(group.count == 1 ? "1 item" : "\(group.count) items")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FlowTheme.muted)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.indices, id: \.self) { index in
                    if rawItems.indices.contains(index) {
                        ActionItemTaskRow(
                            raw: rawItems[index],
                            accent: style.tint,
                            candidates: candidates
                        ) { updated in
                            onChange(index, updated)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(style.soft.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(style.tint.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct AssigneeBadge: View {
    let assignee: String?
    let style: AssigneePersona.Style

    private var label: String { assignee ?? ParsedActionItem.unassignedLabel }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: style.icon)
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(style.tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(style.soft, in: Capsule())
        .overlay(Capsule().stroke(style.tint.opacity(0.28), lineWidth: 1))
        .accessibilityLabel(label)
    }
}

private struct ActionItemTaskRow: View {
    let raw: String
    let accent: Color
    let candidates: [String]
    let onChange: (String) -> Void

    @State private var showingAddAssignee = false
    @State private var draftAssignee = ""

    private var parsed: ParsedActionItem { ParsedActionItem.parse(raw) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                onChange(ParsedActionItem.setDone(raw, done: !parsed.isDone))
            } label: {
                Image(systemName: parsed.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(parsed.isDone ? accent : accent.opacity(0.7))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 1)
            .help(parsed.isDone ? "Mark not done" : "Mark done")
            .accessibilityLabel(parsed.isDone ? "Completed" : "Not completed")
            .accessibilityAddTraits(.isButton)

            Text(parsed.task.isEmpty ? ParsedActionItem.strippingDoneMarker(raw) : parsed.task)
                .font(.system(size: 14))
                .foregroundStyle(FlowTheme.ink.opacity(parsed.isDone ? 0.42 : 0.92))
                .strikethrough(parsed.isDone, color: FlowTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            reassignMenu
        }
        .animation(.easeOut(duration: 0.15), value: parsed.isDone)
        .alert("Add assignee", isPresented: $showingAddAssignee) {
            TextField("Name", text: $draftAssignee)
            Button("Assign") {
                commitDraftAssignee()
            }
            Button("Cancel", role: .cancel) {
                draftAssignee = ""
            }
        } message: {
            Text("Who should own this action item?")
        }
    }

    private var reassignMenu: some View {
        Menu {
            Button(ParsedActionItem.unassignedLabel) {
                assign(nil)
            }
            if !candidates.isEmpty {
                Divider()
            }
            ForEach(candidates, id: \.self) { name in
                Button(name) {
                    assign(name)
                }
            }
            Divider()
            Button("Add assignee…") {
                draftAssignee = ""
                // The menu has to finish dismissing or the alert never appears.
                DispatchQueue.main.async {
                    showingAddAssignee = true
                }
            }
        } label: {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FlowTheme.muted)
                .frame(width: 24, height: 24)
                .background(FlowTheme.card.opacity(0.7), in: Circle())
                .overlay(Circle().stroke(FlowTheme.hairline, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Assign this action item")
    }

    private func commitDraftAssignee() {
        let typed = draftAssignee.trimmingCharacters(in: .whitespacesAndNewlines)
        draftAssignee = ""
        guard !typed.isEmpty else { return }
        assign(ParsedActionItem.assigneeName(typed: typed))
    }

    private func assign(_ name: String?) {
        let task = parsed.task.isEmpty ? ParsedActionItem.strippingDoneMarker(raw) : parsed.task
        let next = ParsedActionItem.compose(task: task, assignee: name, done: parsed.isDone)
        guard next != raw else { return }
        onChange(next)
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

    private var openItems: [String] {
        note.actionItems.filter { !ParsedActionItem.parse($0).isDone }
    }

    private var remindersSheetSummary: String {
        if itemCount == 0 {
            return "Every action item in “\(note.title)” is already checked off."
        }
        let noun = itemCount == 1 ? "action item" : "action items"
        let skipped = note.actionItems.count - itemCount
        if skipped > 0 {
            return "Add \(itemCount) open \(noun) from “\(note.title)” to a list. Checked-off items are skipped."
        }
        return "Add \(itemCount) \(noun) from “\(note.title)” to a list."
    }

    private var itemCount: Int { openItems.count }
    private var groups: [ActionItemGroup] { ActionItemGroup.groups(from: openItems) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Send to Reminders")
                .font(.system(size: 20, weight: .semibold))

            Text(remindersSheetSummary)
                .font(.system(size: 13))
                .foregroundStyle(FlowTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if !reminders.isAuthorized {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Fn Dictate needs access to Reminders.")
                        .font(.system(size: 13))
                    if reminders.needsOpenSettings {
                        Text(RemindersServiceError.notAuthorized.localizedDescription)
                            .font(.system(size: 12))
                            .foregroundStyle(FlowTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Reminders Settings") {
                            reminders.openRemindersSettings()
                        }
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Button(isBusy ? "Waiting for permission…" : "Allow Reminders Access") {
                            Task { await requestRemindersAccess() }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isBusy)
                    }
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

                consolidatedPreview
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
                    .disabled(isBusy || itemCount == 0 || (selectedListID ?? reminders.resolvedListID()) == nil)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(FlowTheme.cream)
        .task {
            // Refresh only — do not auto-prompt. Requesting behind this sheet can hide
            // the system dialog and leave the UI stuck on “Allow Reminders Access”.
            reminders.refreshStatus()
            if reminders.isAuthorized {
                reminders.reloadLists()
                selectedListID = reminders.resolvedListID()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // User may have flipped the toggle in System Settings while this sheet is open.
            reminders.refreshStatus()
            if reminders.isAuthorized {
                reminders.reloadLists()
                selectedListID = reminders.resolvedListID() ?? selectedListID
                statusMessage = nil
            }
        }
    }

    private var consolidatedPreview: some View {
        let previewLimit = 8
        var remaining = previewLimit
        var rows: [(group: ActionItemGroup, tasks: [String])] = []
        for group in groups {
            guard remaining > 0 else { break }
            let tasks = group.indices.compactMap { index -> String? in
                guard openItems.indices.contains(index) else { return nil }
                let parsed = ParsedActionItem.parse(openItems[index])
                return parsed.task.isEmpty ? openItems[index] : parsed.task
            }
            let slice = Array(tasks.prefix(remaining))
            remaining -= slice.count
            rows.append((group, slice))
        }

        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let style = AssigneePersona.style(for: row.group.assignee)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: style.icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(style.tint)
                        Text(row.group.displayName)
                            .font(.system(size: 12, weight: .semibold))
                        Text("\(row.group.count)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(style.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(style.soft, in: Capsule())
                    }
                    ForEach(Array(row.tasks.enumerated()), id: \.offset) { _, task in
                        Text("• \(task)")
                            .font(.system(size: 12))
                            .foregroundStyle(FlowTheme.ink.opacity(0.85))
                            .lineLimit(2)
                    }
                }
            }
            if itemCount > previewLimit {
                Text("+\(itemCount - previewLimit) more")
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

    private func requestRemindersAccess() async {
        isBusy = true
        statusMessage = nil
        defer { isBusy = false }
        let granted = await reminders.requestAccess()
        if granted {
            selectedListID = reminders.resolvedListID()
            statusMessage = nil
        } else if reminders.needsOpenSettings {
            statusMessage = RemindersServiceError.notAuthorized.localizedDescription
        } else {
            statusMessage = RemindersServiceError.notAuthorized.localizedDescription
        }
    }

    private func send() {
        guard let listID = selectedListID ?? reminders.resolvedListID() else { return }
        isBusy = true
        statusMessage = nil
        defer { isBusy = false }
        do {
            let count = try reminders.addActionItems(
                openItems,
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

private struct VoiceSpeakerLabel: View {
    let speaker: String
    let voiceID: UUID?
    var fontSize: CGFloat = 12
    var width: CGFloat = 96
    var onRename: (UUID, String) -> Void

    @State private var isEditing = false
    @State private var draft = ""

    private var canRename: Bool {
        voiceID != nil && speaker.caseInsensitiveCompare("You") != .orderedSame
    }

    var body: some View {
        Text(speaker)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(FlowTheme.muted)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                guard canRename else { return }
                draft = VoiceProfile.isGeneric(speaker) ? "" : speaker
                isEditing = true
            }
            .help(canRename ? "Name this voice — remembered in later meetings" : "")
            .popover(isPresented: $isEditing, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Who is this?")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Saved on this Mac and used in future meetings.")
                        .font(.system(size: 11))
                        .foregroundStyle(FlowTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("Name", text: $draft, prompt: Text(speaker))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .onSubmit(commit)
                    HStack {
                        Spacer()
                        Button("Save", action: commit)
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(12)
            }
    }

    private func commit() {
        guard let voiceID else { return }
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        onRename(voiceID, name)
        isEditing = false
    }
}
