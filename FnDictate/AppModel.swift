import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case idle
        case listening
        case processing
        case meetingRecording
        case meetingProcessing
    }

    var phase: Phase = .idle
    var partialText = ""
    var audioLevel: Float = 0
    /// System-audio (Others) level for dual-channel live chrome.
    var remoteAudioLevel: Float = 0
    /// Which meeting channel is currently "hot" for UI (nil when idle / both quiet).
    var activeMeetingChannel: MeetingChannel?
    /// Live Accessibility roster names (best-effort).
    var liveParticipantRoster: [String] = []
    /// Display label for the remote channel ("Others" or calendar 1:1 name).
    var remoteSpeakerLabel = "Others"

    enum MeetingChannel: Equatable, Sendable {
        case you
        case others
    }

    var statusMessage = "Hold Fn · double-tap hands-free"
    enum LibraryTab: Equatable {
        case dictations
        case dictionary
        case meetings
    }

    var showOnboarding = false
    var showLibrary = false
    /// When set, Library switches to this tab on next appear/change.
    var requestedLibraryTab: LibraryTab?
    var highlightedMeetingID: UUID?
    var lastError: String?
    var includeSystemAudioInMeetings = true
    /// When on, stop meeting recording once the detected Zoom/Teams/Meet call disappears.
    var autoStopRecordingWhenMeetingEnds: Bool = true {
        didSet {
            UserDefaults.standard.set(autoStopRecordingWhenMeetingEnds, forKey: autoStopMeetingKey)
        }
    }
    var activeMeetingID: UUID?
    var detectedMeeting: DetectedMeeting?
    var showMeetingPrompt = false
    /// Manual expand of the Wispr-style edge rail (collapsed by default).
    var flowSidebarExpanded = false
    /// Meeting prompt tucked into the rail (Not now still snoozes fully).
    var meetingPromptMinimized = false
    /// Listening/meeting transcript pill tucked down to a waveform chip.
    var listeningPillCollapsed = false
    /// Live catch-up answer shown during / after a meeting.
    var meetingCatchUp: String?
    /// Answer from ask-across-history.
    var meetingAskAnswer: String?
    var meetingAskBusy = false
    /// Upcoming calendar context (for day card / brief).
    var upcomingCalendarMeeting: CalendarMeetingContext?
    var upcomingBrief: String?
    /// Effective cleanup tone for the current / last frontmost app (shown on the pill).
    var currentTone: CleanupTone = .light
    /// Bumps when per-app tone overrides change (Edit preview / Formatting list refresh).
    var toneSettingsVersion = 0

    /// True when dictation was started via double-tap (stays on until tap/Esc).
    private var handsFreeDictation = false
    /// App that had focus when dictation started — restored before paste.
    @ObservationIgnored private var dictationTargetApp: NSRunningApplication?
    private var toneOverrides: [String: String] = [:]
    private let toneOverridesKey = "FnDictate.toneOverrides"
    private let didMineHistoryKey = "FnDictate.didMineHistoryForDictionary"
    private let setupCompletedKey = "FnDictate.setupCompleted"
    private let learnFromInAppKey = "FnDictate.learnFromInAppCorrections"
    private let autoStopMeetingKey = "FnDictate.autoStopRecordingWhenMeetingEnds"

    let permissions = PermissionManager()
    let history = HistoryStore()
    let meetings = MeetingStore()
    let dictionary = DictionaryStore()
    let calendar = CalendarMeetingService()
    let reminders = RemindersService()

    /// When on, watches the focused field after paste and learns spelling fixes made in-app.
    var learnFromInAppCorrections: Bool = true {
        didSet {
            UserDefaults.standard.set(learnFromInAppCorrections, forKey: learnFromInAppKey)
            if !learnFromInAppCorrections {
                correctionWatcher.cancel()
            }
        }
    }

    private let fnMonitor = FnKeyMonitor()
    private let meetingHotKey = MeetingHotKeyMonitor()
    private let meetingDetector = MeetingDetector()
    private let mic = MicrophoneCapture()
    private let cleaner = TextCleaner()
    private let meetingIntelligence = MeetingIntelligence()
    private let correctionWatcher = InAppCorrectionWatcher()
    private var speech: SpeechTranscriptionService?
    /// Second analyzer for system-audio channel during meetings (Others).
    private var speechRemote: SpeechTranscriptionService?
    private var systemAudio: SystemAudioCapture?
    private var listeningPill: NSPanel?
    private var meetingPromptPanel: NSPanel?
    /// AppKit-backed Library window used when SwiftUI openWindow isn't available yet.
    @ObservationIgnored private var libraryWindow: NSWindow?
    /// Opens the Setup window (wired from AppDelegate / menu bar).
    @ObservationIgnored var presentOnboardingHandler: (() -> Void)?
    private var didBootstrap = false
    private let idleStatus = "Hold Fn · double-tap hands-free"
    private var meetingStartedAt: Date?
    private var lastCatchUpOffset: TimeInterval = 0
    private var activeMeetingPartialYou = ""
    private var activeMeetingPartialOthers = ""
    /// Set when ScreenCaptureKit fails at meeting start.
    private var activeMeetingSystemAudioFailed = false
    /// App name (Zoom / Teams / …) this recording is bound to for auto-stop; nil = manual note.
    private var recordingMeetingAppName: String?
    /// In-flight note refinement tasks (stop + manual retry).
    private var meetingRefineTasks: [UUID: Task<Void, Never>] = [:]
    /// Polls Accessibility for participant tiles during an active meeting.
    private var rosterPollTask: Task<Void, Never>?
    /// Decay remote level when buffers pause.
    private var lastYouSpeechAt: Date?
    private var lastOthersSpeechAt: Date?

    private var hasCompletedSetup: Bool {
        get { UserDefaults.standard.bool(forKey: setupCompletedKey) }
        set { UserDefaults.standard.set(newValue, forKey: setupCompletedKey) }
    }

    /// Opens Library via a retained AppKit window (dock / early activation safe).
    func presentLibraryWindow() {
        bootstrap()
        showLibrary = true
        NSApp.activate(ignoringOtherApps: true)

        if let existing = NSApp.windows.first(where: {
            $0.identifier?.rawValue == Self.libraryWindowIdentifier
        }) {
            libraryWindow = existing
            existing.identifier = NSUserInterfaceItemIdentifier(Self.libraryWindowIdentifier)
            existing.isReleasedWhenClosed = false
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            return
        }

        if let libraryWindow {
            libraryWindow.makeKeyAndOrderFront(nil)
            libraryWindow.orderFrontRegardless()
            return
        }

        let hosting = NSHostingController(rootView: LibraryView(model: self))
        let window = NSWindow(contentViewController: hosting)
        window.identifier = NSUserInterfaceItemIdentifier(Self.libraryWindowIdentifier)
        window.title = LibraryView.LibrarySection.dictations.help
        window.setContentSize(NSSize(width: 1120, height: 720))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setFrameAutosaveName("FnDictate.Library")
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        libraryWindow = window
    }

    static let libraryWindowIdentifier = "library"

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true

        loadToneOverrides()
        if UserDefaults.standard.object(forKey: learnFromInAppKey) == nil {
            learnFromInAppCorrections = true
        } else {
            learnFromInAppCorrections = UserDefaults.standard.bool(forKey: learnFromInAppKey)
        }
        if UserDefaults.standard.object(forKey: autoStopMeetingKey) == nil {
            autoStopRecordingWhenMeetingEnds = true
        } else {
            autoStopRecordingWhenMeetingEnds = UserDefaults.standard.bool(forKey: autoStopMeetingKey)
        }
        permissions.refresh()
        calendar.refreshStatus()
        refreshUpcomingCalendar()
        if permissions.allRequiredGranted {
            hasCompletedSetup = true
            showOnboarding = false
        } else {
            // Don't re-nag after the user dismissed Setup (common with Xcode rebuilds
            // resetting Accessibility trust). Menu → Permissions still opens it.
            showOnboarding = !hasCompletedSetup
        }

        if #available(macOS 26, *) {
            speech = SpeechTranscriptionService()
            speechRemote = SpeechTranscriptionService()
        }

        mineHistoryIntoDictionaryIfNeeded()

        Task {
            await cleaner.prewarm()
            if let speech {
                try? await speech.prewarm()
            }
            if let speechRemote {
                try? await speechRemote.prewarm()
            }
            await refreshUpcomingBriefIfNeeded()
        }

        startHotkeysIfPossible()
        startMeetingDetection()
        presentFlowSidebar()
        refreshCurrentTone()
    }

    /// Cycles Raw → Light → Polished for the frontmost app and persists the override.
    func cycleTone() {
        let (bundleID, _) = TextPaster.frontmostApp()
        let next = currentTone.next
        if let bundleID, !bundleID.isEmpty {
            setTone(next, forBundleID: bundleID)
        } else {
            currentTone = next
        }
    }

    func effectiveTone(bundleID: String?, name: String?) -> CleanupTone {
        if let bundleID,
           let raw = toneOverrides[bundleID],
           let override = CleanupTone(rawValue: raw)
        {
            return override
        }
        return CleanupTone.forApp(bundleID: bundleID, name: name)
    }

    func setTone(_ tone: CleanupTone, forBundleID bundleID: String) {
        guard !bundleID.isEmpty else { return }
        toneOverrides[bundleID] = tone.rawValue
        saveToneOverrides()
        toneSettingsVersion += 1
        let (frontID, _) = TextPaster.frontmostApp()
        if frontID == bundleID {
            currentTone = tone
        }
    }

    func resetTone(forBundleID bundleID: String) {
        guard !bundleID.isEmpty else { return }
        toneOverrides.removeValue(forKey: bundleID)
        saveToneOverrides()
        toneSettingsVersion += 1
        let (frontID, frontName) = TextPaster.frontmostApp()
        if frontID == bundleID {
            currentTone = effectiveTone(bundleID: frontID, name: frontName)
        }
    }

    func hasToneOverride(forBundleID bundleID: String) -> Bool {
        toneOverrides[bundleID] != nil
    }

    /// Runs the same cleanup used at paste time (for Edit Formatted preview).
    func cleanedText(_ text: String, tone: CleanupTone) async -> String {
        await cleaner.clean(text, tone: tone)
    }

    /// Curated defaults + history apps + orphan overrides for Library → Formatting.
    var formattingProfiles: [FormattingProfile] {
        var seen = Set<String>()
        var profiles: [FormattingProfile] = []

        for app in FormattingDefaults.curatedApps {
            seen.insert(app.bundleID)
            let tone = effectiveTone(bundleID: app.bundleID, name: app.name)
            profiles.append(
                FormattingProfile(
                    id: app.bundleID,
                    name: app.name,
                    bundleID: app.bundleID,
                    tone: tone,
                    isOverride: hasToneOverride(forBundleID: app.bundleID),
                    isCatchAll: false
                )
            )
        }

        // History apps not already curated (newest first, unique by bundle ID).
        for entry in history.entries {
            guard let bundleID = entry.appBundleID, !bundleID.isEmpty, !seen.contains(bundleID) else {
                continue
            }
            seen.insert(bundleID)
            let trimmedName = entry.appName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let display = trimmedName.isEmpty
                ? AppDisplayName.short(name: entry.appName, bundleID: bundleID)
                : trimmedName
            profiles.append(
                FormattingProfile(
                    id: bundleID,
                    name: display,
                    bundleID: bundleID,
                    tone: effectiveTone(bundleID: bundleID, name: entry.appName),
                    isOverride: hasToneOverride(forBundleID: bundleID),
                    isCatchAll: false
                )
            )
        }

        for bundleID in toneOverrides.keys.sorted() where !seen.contains(bundleID) {
            seen.insert(bundleID)
            let name = AppDisplayName.short(name: nil, bundleID: bundleID)
            profiles.append(
                FormattingProfile(
                    id: bundleID,
                    name: name,
                    bundleID: bundleID,
                    tone: effectiveTone(bundleID: bundleID, name: nil),
                    isOverride: true,
                    isCatchAll: false
                )
            )
        }

        profiles.append(
            FormattingProfile(
                id: FormattingDefaults.catchAllID,
                name: "Other apps",
                bundleID: nil,
                tone: .light,
                isOverride: false,
                isCatchAll: true
            )
        )

        return profiles
    }

    private func refreshCurrentTone() {
        let (bundleID, name) = TextPaster.frontmostApp()
        currentTone = effectiveTone(bundleID: bundleID, name: name)
    }

    private func loadToneOverrides() {
        toneOverrides = UserDefaults.standard.dictionary(forKey: toneOverridesKey) as? [String: String] ?? [:]
    }

    private func saveToneOverrides() {
        UserDefaults.standard.set(toneOverrides, forKey: toneOverridesKey)
    }

    private func mineHistoryIntoDictionaryIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: didMineHistoryKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: didMineHistoryKey) }

        for entry in history.entries.prefix(50) {
            guard let original = entry.originalText,
                  original.caseInsensitiveCompare(entry.text) != .orderedSame
            else { continue }
            dictionary.learn(from: original, to: entry.text)
        }
    }

    func startMeetingDetection() {
        meetingDetector.onMeetingDetected = { [weak self] meeting in
            Task { @MainActor in
                self?.handleMeetingDetected(meeting)
            }
        }
        meetingDetector.onMeetingEnded = { [weak self] ended in
            Task { @MainActor in
                self?.handleMeetingDetectionEnded(ended)
            }
        }
        meetingDetector.start()
    }

    private func handleMeetingDetected(_ meeting: DetectedMeeting) {
        detectedMeeting = meeting
        // Don't interrupt active work with the prompt.
        guard phase == .idle else { return }
        showMeetingPrompt = true
        meetingPromptMinimized = false
        flowSidebarExpanded = false
        updateFlowSidebarPanel()
    }

    private func handleMeetingDetectionEnded(_ ended: DetectedMeeting) {
        detectedMeeting = nil
        if showMeetingPrompt {
            showMeetingPrompt = false
            meetingPromptMinimized = false
            updateFlowSidebarPanel()
        }

        guard autoStopRecordingWhenMeetingEnds,
              phase == .meetingRecording,
              let boundApp = recordingMeetingAppName,
              boundApp.caseInsensitiveCompare(ended.appName) == .orderedSame
        else { return }

        // Clear binding first so a flaky second end signal can't double-stop.
        recordingMeetingAppName = nil
        statusMessage = "Meeting ended — saving…"
        Task { await stopMeeting() }
    }

    func dismissMeetingPrompt() {
        meetingDetector.dismissCurrent()
        showMeetingPrompt = false
        meetingPromptMinimized = false
        flowSidebarExpanded = false
        updateFlowSidebarPanel()
    }

    func acceptDetectedMeeting() {
        includeSystemAudioInMeetings = true
        showMeetingPrompt = false
        meetingPromptMinimized = false
        flowSidebarExpanded = false
        updateFlowSidebarPanel()
        toggleMeeting()
    }

    func toggleFlowSidebar() {
        if showMeetingPrompt, meetingPromptMinimized {
            meetingPromptMinimized = false
        } else if showMeetingPrompt {
            meetingPromptMinimized = true
        } else {
            flowSidebarExpanded.toggle()
        }
        updateFlowSidebarPanel()
    }

    func collapseFlowSidebar() {
        if showMeetingPrompt {
            meetingPromptMinimized = true
        }
        flowSidebarExpanded = false
        updateFlowSidebarPanel()
    }

    func presentFlowSidebar() {
        updateFlowSidebarPanel()
    }

    func startHotkeysIfPossible() {
        permissions.refresh()
        guard permissions.accessibilityTrusted else { return }

        fnMonitor.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleHotkey(event)
            }
        }

        meetingHotKey.onToggle = { [weak self] in
            Task { @MainActor in
                self?.handleMeetingHotKey()
            }
        }

        do {
            try fnMonitor.start()
            statusMessage = idleStatus
        } catch {
            lastError = "Could not start Fn key monitor. Grant Accessibility via Permissions, then quit & relaunch."
        }

        do {
            try meetingHotKey.start()
        } catch {
            // Optional backup shortcut — detection prompt is primary for meetings.
            lastError = error.localizedDescription
        }
    }

    func refreshPermissionsAndMaybeStart() {
        permissions.refresh()
        if permissions.allRequiredGranted {
            completeSetup()
            startHotkeysIfPossible()
        }
    }

    /// Marks Setup as done and hides it (permissions granted, or user chose Not now).
    func completeSetup() {
        hasCompletedSetup = true
        showOnboarding = false
    }

    /// Re-opens Setup (menu Permissions, or a feature that needs a missing grant).
    func requestSetup(reason: String? = nil) {
        if let reason {
            lastError = reason
        }
        showOnboarding = true
        presentOnboardingHandler?()
    }

    private func handleHotkey(_ event: FnKeyMonitor.Event) {
        switch event {
        case .holdBegan:
            guard phase == .idle else { return }
            handsFreeDictation = false
            Task { await beginDictation() }
        case .holdEnded:
            guard phase == .listening, !handsFreeDictation else { return }
            Task { await endDictation(cancel: false) }
        case .doubleTap:
            if phase == .listening, handsFreeDictation {
                Task { await endDictation(cancel: false) }
            } else if phase == .idle {
                handsFreeDictation = true
                Task { await beginDictation() }
            }
        case .singleTap:
            // Single tap stops hands-free; ignored when idle.
            if phase == .listening, handsFreeDictation {
                Task { await endDictation(cancel: false) }
            }
        case .cancel:
            if phase == .listening {
                Task { await endDictation(cancel: true) }
            }
        }
    }

    private func handleMeetingHotKey() {
        // Don't interrupt an in-progress dictation session.
        guard phase != .listening, phase != .processing, phase != .meetingProcessing else {
            lastError = "Finish dictation before starting a meeting (release Fn)."
            return
        }
        NSSound.beep()
        toggleMeeting()
    }

    private func beginDictation() async {
        permissions.refresh()
        guard permissions.microphoneGranted else {
            requestSetup(reason: "Microphone permission required.")
            return
        }
        guard let speech else {
            lastError = "SpeechAnalyzer requires macOS 26+."
            return
        }

        // Don't keep watching a previous paste while a new dictation starts.
        correctionWatcher.cancel()

        phase = .listening
        partialText = ""
        statusMessage = "Listening…"
        dictationTargetApp = TextPaster.frontmostTargetApp()
        refreshCurrentTone()
        showListeningPill(true)

        do {
            await speech.setPartialHandler { [weak self] text in
                Task { @MainActor in
                    self?.partialText = text
                }
            }
            try await speech.startSession(contextualStrings: dictionaryHints())
            mic.onBuffer = { buffer in
                let packet = SendablePCMBuffer(buffer: buffer)
                Task {
                    await speech.append(packet)
                }
            }
            mic.onLevel = { [weak self] level in
                Task { @MainActor in
                    self?.audioLevel = level
                }
            }
            try mic.start()
        } catch {
            lastError = error.localizedDescription
            mic.stop()
            await speech.cancel()
            phase = .idle
            audioLevel = 0
            statusMessage = idleStatus
            showListeningPill(false)
        }
    }

    private func endDictation(cancel: Bool) async {
        mic.stop()
        audioLevel = 0
        handsFreeDictation = false

        guard let speech else {
            phase = .idle
            dictationTargetApp = nil
            showListeningPill(false)
            return
        }

        if cancel {
            await speech.cancel()
            partialText = ""
            phase = .idle
            statusMessage = "Cancelled"
            dictationTargetApp = nil
            showListeningPill(false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.statusMessage = "Hold Fn · double-tap hands-free"
            }
            return
        }

        // Hide the pill immediately — the brief "Processing" flash of cleaned text
        // was never readable long enough to be useful.
        phase = .processing
        statusMessage = "Transcribing…"
        showListeningPill(false)
        partialText = ""

        let raw = await speech.finish()
        let commanded = VoiceCommandProcessor.process(raw)
        let target = dictationTargetApp ?? TextPaster.frontmostTargetApp()
        let bundleID = target?.bundleIdentifier
        let name = target?.localizedName
        let tone = effectiveTone(bundleID: bundleID, name: name)
        currentTone = tone
        statusMessage = "Cleaning up…"
        let cleaned = await cleaner.clean(commanded, tone: tone)
        let finalized = dictionary.apply(to: cleaned)

        if !finalized.isEmpty {
            await pasteIntoTarget(finalized, app: target)
            let entry = TranscriptEntry(
                text: finalized,
                originalText: raw,
                appName: name,
                appBundleID: bundleID
            )
            history.add(entry)
            statusMessage = "Pasted"

            let learnFrom = raw
            let learnTo = finalized
            Task { @MainActor [weak self] in
                guard let self, learnFrom.caseInsensitiveCompare(learnTo) != .orderedSame else { return }
                self.dictionary.learn(from: learnFrom, to: learnTo)
            }

            startInAppCorrectionWatch(pasted: finalized, targetApp: target, historyEntryID: entry.id)
        } else {
            statusMessage = "No speech detected"
        }

        dictationTargetApp = nil
        phase = .idle
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard self?.phase == .idle else { return }
            self?.statusMessage = "Hold Fn · double-tap hands-free"
        }
    }

    /// Restore the original frontmost app, then paste so ⌘V hits their field.
    private func pasteIntoTarget(_ text: String, app: NSRunningApplication?) async {
        TextPaster.activate(app)
        // Brief yield so focus / first responder settle after activation.
        try? await Task.sleep(nanoseconds: 80_000_000)
        TextPaster.paste(text)
    }

    private func startInAppCorrectionWatch(
        pasted: String,
        targetApp: NSRunningApplication?,
        historyEntryID: UUID
    ) {
        guard learnFromInAppCorrections, permissions.accessibilityTrusted else { return }

        correctionWatcher.start(
            pasted: pasted,
            targetApp: targetApp,
            historyEntryID: historyEntryID,
            onFailedToAttach: { [weak self] in
                guard let self else { return }
                // Electron apps (esp. Cursor) often hide the chat field from AX.
                self.statusMessage = "Can't see field — ⌘A ⌘C after edits, or fix in Library"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
                    guard self?.phase == .idle else { return }
                    self?.statusMessage = self?.idleStatus ?? "Hold Fn · double-tap hands-free"
                }
            }
        ) { [weak self] result in
            guard let self else { return }
            self.handleInAppCorrection(pasted: pasted, result: result)
        }
    }

    private func handleInAppCorrection(pasted: String, result: InAppCorrectionWatcher.Result) {
        let corrected = result.correctedPaste
        guard corrected != pasted else { return }
        // Belt-and-suspenders: never revise history from Cursor UI chrome / unrelated AX reads.
        guard InAppCorrectionWatcher.isPlausibleCorrection(pasted: pasted, corrected: corrected)
        else { return }

        let learned = dictionary.learn(from: pasted, to: corrected)

        if let id = result.historyEntryID,
           let entry = history.entries.first(where: { $0.id == id })
        {
            var updated = entry
            if updated.originalText == nil {
                updated.originalText = entry.text
            }
            updated.text = corrected
            updated.updatedAt = .now
            history.update(updated)
        }

        guard learned > 0 else { return }
        statusMessage = learned == 1
            ? "Learned 1 correction"
            : "Learned \(learned) corrections"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard self?.phase == .idle else { return }
            self?.statusMessage = self?.idleStatus ?? "Hold Fn · double-tap hands-free"
        }
    }

    // MARK: - Meetings

    func toggleMeeting() {
        if phase == .meetingRecording {
            Task { await stopMeeting() }
        } else if phase == .idle {
            Task { await startMeeting() }
        }
    }

    private func startMeeting() async {
        permissions.refresh()
        guard permissions.microphoneGranted else {
            requestSetup(reason: "Microphone permission required for meetings.")
            return
        }
        guard let speech else {
            lastError = "SpeechAnalyzer requires macOS 26+."
            return
        }

        correctionWatcher.cancel()
        meetingCatchUp = nil
        lastCatchUpOffset = 0
        activeMeetingPartialYou = ""
        activeMeetingPartialOthers = ""
        activeMeetingSystemAudioFailed = false
        remoteAudioLevel = 0
        activeMeetingChannel = nil
        liveParticipantRoster = []
        meetingStartedAt = .now

        refreshUpcomingCalendar()
        let cal = upcomingCalendarMeeting
        let title = cal?.title
            ?? "Meeting \(Date().formatted(date: .abbreviated, time: .shortened))"
        let attendees = cal?.attendees ?? []
        let oneOnOne = cal?.remoteOneOnOneName
        remoteSpeakerLabel = oneOnOne ?? "Others"

        let note = MeetingNote(
            title: title,
            includeSystemAudio: includeSystemAudioInMeetings,
            attendees: attendees,
            calendarEventIdentifier: cal?.eventIdentifier,
            calendarTitle: cal?.title,
            brief: upcomingBrief,
            processingState: .idle,
            sourceAppName: detectedMeeting?.appName,
            remoteOneOnOneName: oneOnOne
        )
        meetings.upsert(note)
        activeMeetingID = note.id
        // Bind auto-stop to the call we started with (not a later unrelated app).
        recordingMeetingAppName = detectedMeeting?.appName
        selectedMeetingFocus(note.id)

        phase = .meetingRecording
        statusMessage = recordingMeetingAppName.map { "Recording \($0)…" } ?? "Recording meeting…"
        partialText = ""
        showListeningPill(true)
        requestedLibraryTab = .meetings
        showLibrary = true
        presentLibraryWindow()
        startRosterPolling()

        let hints = meetingHints(attendees: attendees)

        do {
            await speech.setPartialHandler { [weak self] text in
                Task { @MainActor in
                    self?.activeMeetingPartialYou = text
                    self?.refreshMeetingPartialDisplay()
                }
            }
            await speech.setFinalSegmentHandler { [weak self] text, offset in
                Task { @MainActor in
                    self?.appendMeetingSegment(text: text, offset: offset, speaker: "You")
                }
            }
            try await speech.startSession(contextualStrings: hints)

            mic.onBuffer = { buffer in
                let packet = SendablePCMBuffer(buffer: buffer)
                Task { await speech.append(packet) }
            }
            mic.onLevel = { [weak self] level in
                Task { @MainActor in
                    self?.audioLevel = level
                    self?.noteChannelActivity(youLevel: level, othersLevel: nil)
                }
            }
            try mic.start()

            if includeSystemAudioInMeetings {
                permissions.refresh()
                if !permissions.screenRecordingGranted {
                    _ = await permissions.requestScreenRecording()
                }

                if permissions.screenRecordingGranted,
                   let remote = speechRemote,
                   remote !== speech
                {
                    let remoteLabel = remoteSpeakerLabel
                    await remote.setPartialHandler { [weak self] text in
                        Task { @MainActor in
                            self?.activeMeetingPartialOthers = text
                            self?.refreshMeetingPartialDisplay()
                        }
                    }
                    await remote.setFinalSegmentHandler { [weak self] text, offset in
                        Task { @MainActor in
                            self?.appendMeetingSegment(text: text, offset: offset, speaker: remoteLabel)
                        }
                    }
                    try await remote.startSession(contextualStrings: hints)

                    let capture = SystemAudioCapture()
                    capture.onBuffer = { buffer in
                        let packet = SendablePCMBuffer(buffer: buffer)
                        Task { await remote.append(packet) }
                    }
                    capture.onLevel = { [weak self] level in
                        Task { @MainActor in
                            self?.remoteAudioLevel = level
                            self?.noteChannelActivity(youLevel: nil, othersLevel: level)
                        }
                    }
                    do {
                        try await capture.start()
                        systemAudio = capture
                    } catch {
                        activeMeetingSystemAudioFailed = true
                        lastError = "System audio unavailable (\(error.localizedDescription)). Continuing with microphone only — other speakers may appear as You. If you just granted Screen Recording, quit Fn Dictate completely and relaunch."
                        permissions.openScreenRecordingSettings()
                        markActiveMeetingSystemAudioFailed()
                    }
                } else {
                    activeMeetingSystemAudioFailed = true
                    if !permissions.screenRecordingGranted {
                        lastError = "Screen Recording is required to capture other participants. Enable Fn Dictate in System Settings → Privacy & Security → Screen & System Audio Recording, then fully quit and relaunch the app."
                        permissions.openScreenRecordingSettings()
                    } else {
                        lastError = "System audio transcription isn't available. Continuing with microphone only."
                    }
                    markActiveMeetingSystemAudioFailed()
                }
            }
        } catch {
            lastError = error.localizedDescription
            await cancelMeetingRecording()
        }
    }

    private func stopMeeting() async {
        guard phase == .meetingRecording else { return }
        phase = .meetingProcessing
        statusMessage = statusMessage.hasPrefix("Meeting ended")
            ? statusMessage
            : "Saving meeting…"
        stopRosterPolling()
        mic.stop()
        audioLevel = 0
        remoteAudioLevel = 0
        activeMeetingChannel = nil
        let capture = systemAudio
        systemAudio = nil
        if let capture {
            await capture.stop()
        }
        showListeningPill(false)

        var youText = ""
        var othersText = ""
        if let speech {
            youText = await speech.finish()
            await speech.setFinalSegmentHandler(nil)
            await speech.setPartialHandler(nil)
        }
        if includeSystemAudioInMeetings, let remote = speechRemote, remote !== speech {
            othersText = await remote.finish()
            await remote.setFinalSegmentHandler(nil)
            await remote.setPartialHandler(nil)
        }

        guard let id = activeMeetingID else {
            phase = .idle
            statusMessage = idleStatus
            return
        }

        var note = meetings.notes.first(where: { $0.id == id }) ?? MeetingNote(id: id)
        note.systemAudioCaptureFailed = note.systemAudioCaptureFailed || activeMeetingSystemAudioFailed
        // Fold leftover finish() text using the live remote label (1:1 name or Others).
        mergeLeftoverMeetingText(
            into: &note,
            youText: youText,
            othersText: othersText,
            remoteSpeaker: note.remoteOneOnOneName ?? "Others"
        )

        // Snapshot latest roster onto the note before refine.
        if !liveParticipantRoster.isEmpty {
            note.participantRoster = liveParticipantRoster
        }

        let rawLabeled = note.labeledTranscript.isEmpty
            ? [youText, othersText].filter { !$0.isEmpty }.joined(separator: "\n")
            : note.labeledTranscript
        let withDictionary = dictionary.apply(to: rawLabeled)

        note.endedAt = .now
        note.transcript = withDictionary
        note.processingState = .processing
        note.processingMessage = "Generating summary, action items, and speakers…"
        meetings.upsert(note)

        activeMeetingID = nil
        meetingStartedAt = nil
        recordingMeetingAppName = nil
        activeMeetingSystemAudioFailed = false
        liveParticipantRoster = []
        remoteSpeakerLabel = "Others"
        highlightedMeetingID = note.id
        requestedLibraryTab = .meetings
        showLibrary = true
        presentLibraryWindow()
        phase = .idle
        statusMessage = "Processing meeting notes…"
        partialText = ""
        activeMeetingPartialYou = ""
        activeMeetingPartialOthers = ""

        enqueueMeetingRefine(noteID: note.id)
    }

    /// Re-run Apple Intelligence on an existing note (e.g. after a long meeting fallback).
    func reprocessMeeting(id: UUID) {
        guard let note = meetings.notes.first(where: { $0.id == id }) else { return }
        guard note.processingState != .processing else { return }
        var updating = note
        updating.processingState = .processing
        updating.processingMessage = "Generating summary, action items, and speakers…"
        meetings.upsert(updating)
        if phase == .idle {
            statusMessage = "Processing meeting notes…"
        }
        enqueueMeetingRefine(noteID: id)
    }

    private func enqueueMeetingRefine(noteID: UUID) {
        meetingRefineTasks[noteID]?.cancel()
        meetingRefineTasks[noteID] = Task { @MainActor [weak self] in
            await self?.refineMeetingNote(id: noteID)
            self?.meetingRefineTasks[noteID] = nil
        }
    }

    private func refineMeetingNote(id: UUID) async {
        guard var note = meetings.notes.first(where: { $0.id == id }) else { return }
        let result = await meetingIntelligence.refine(
            transcript: note.labeledTranscript.isEmpty ? note.transcript : note.labeledTranscript,
            segments: note.segments,
            attendees: note.attendees,
            calendarTitle: note.calendarTitle,
            dictionaryHints: Array(dictionary.preferredSpellings.prefix(40)),
            rosterNames: note.participantRoster,
            lockedSpeakerRenames: note.lockedSpeakerRenames,
            remoteOneOnOneName: note.remoteOneOnOneName
        )
        guard !Task.isCancelled else { return }
        guard meetings.notes.contains(where: { $0.id == id }) else { return }

        let refined = result.meeting
        if !refined.title.isEmpty {
            note.title = refined.title
        }
        note.transcript = dictionary.apply(
            to: refined.transcript.isEmpty ? note.transcript : refined.transcript
        )
        note.summary = refined.summary
        note.decisions = refined.decisions
        note.actionItems = refined.actionItems
        note.openQuestions = refined.openQuestions
        if !refined.segments.isEmpty {
            note.segments = refined.segments
        }

        // Re-apply locked renames + merge Voice N / casing after any model output.
        let hints = SpeakerLabelNormalizer.IdentityHints(
            calendarAttendees: note.attendees,
            rosterNames: note.participantRoster,
            lockedRenames: note.lockedSpeakerRenames,
            remoteOneOnOneName: note.remoteOneOnOneName
        )
        let merged = SpeakerLabelNormalizer.normalizeNoteFields(
            segments: note.segments,
            transcript: note.transcript,
            hints: hints
        )
        note.segments = merged.segments
        note.transcript = merged.transcript

        var message = result.message
        let speakers = Set(note.segments.map(\.speaker))
        let hasRemote = speakers.contains(where: {
            $0 != "You" && !$0.isEmpty
        })
        if note.includeSystemAudio,
           (note.systemAudioCaptureFailed || (!hasRemote && speakers == ["You"]))
        {
            let speakerHint = note.systemAudioCaptureFailed
                ? "System audio wasn't captured — only your mic is labeled. Enable Screen Recording and retry, or connect Calendar so names can be inferred."
                : "No separate remote audio was captured (headphones/system audio). Connect Calendar so speaker names can be inferred from context."
            if message == nil || result.usedAppleIntelligence {
                message = speakerHint
            }
        }

        note.processingState = result.usedAppleIntelligence ? .complete : .incomplete
        note.processingMessage = message
        meetings.upsert(note)

        if phase == .idle {
            statusMessage = result.usedAppleIntelligence
                ? "Meeting notes ready"
                : "Meeting saved — summary limited"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard self?.phase == .idle else { return }
                self?.statusMessage = self?.idleStatus ?? "Hold Fn · double-tap hands-free"
            }
        }
    }

    private func markActiveMeetingSystemAudioFailed() {
        guard let id = activeMeetingID,
              var note = meetings.notes.first(where: { $0.id == id })
        else { return }
        note.systemAudioCaptureFailed = true
        meetings.upsert(note)
    }

    private func mergeLeftoverMeetingText(
        into note: inout MeetingNote,
        youText: String,
        othersText: String,
        remoteSpeaker: String = "Others"
    ) {
        if note.segments.isEmpty {
            var segs: [MeetingTranscriptSegment] = []
            if !youText.isEmpty {
                segs.append(MeetingTranscriptSegment(startOffset: 0, text: youText, speaker: "You"))
            }
            if !othersText.isEmpty {
                segs.append(
                    MeetingTranscriptSegment(startOffset: 0.1, text: othersText, speaker: remoteSpeaker)
                )
            }
            note.segments = segs
            return
        }

        // If the remote channel never emitted segments, fold finish() text in.
        if !othersText.isEmpty {
            let othersJoined = note.segments
                .filter { $0.speaker != "You" }
                .map(\.text)
                .joined(separator: " ")
            if othersJoined.isEmpty {
                let lastOffset = note.segments.map(\.startOffset).max() ?? 0
                note.segments.append(
                    MeetingTranscriptSegment(
                        startOffset: lastOffset + 0.1,
                        text: dictionary.apply(to: othersText),
                        speaker: remoteSpeaker
                    )
                )
            }
        }
        _ = youText
    }

    private func cancelMeetingRecording() async {
        stopRosterPolling()
        mic.stop()
        audioLevel = 0
        remoteAudioLevel = 0
        activeMeetingChannel = nil
        let capture = systemAudio
        systemAudio = nil
        if let capture {
            await capture.stop()
        }
        if let speech {
            await speech.cancel()
            await speech.setFinalSegmentHandler(nil)
            await speech.setPartialHandler(nil)
        }
        if let remote = speechRemote {
            await remote.cancel()
            await remote.setFinalSegmentHandler(nil)
            await remote.setPartialHandler(nil)
        }
        showListeningPill(false)
        if let id = activeMeetingID {
            if let note = meetings.notes.first(where: { $0.id == id }),
               note.segments.isEmpty,
               note.summary.isEmpty
            {
                meetings.delete(note)
            }
        }
        activeMeetingID = nil
        meetingStartedAt = nil
        recordingMeetingAppName = nil
        activeMeetingSystemAudioFailed = false
        liveParticipantRoster = []
        remoteSpeakerLabel = "Others"
        phase = .idle
        statusMessage = idleStatus
        partialText = ""
        activeMeetingPartialYou = ""
        activeMeetingPartialOthers = ""
    }

    private func appendMeetingSegment(text: String, offset: TimeInterval, speaker: String) {
        let cleaned = dictionary.apply(to: text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let id = activeMeetingID else { return }
        let segment = MeetingTranscriptSegment(
            startOffset: offset,
            text: cleaned,
            speaker: speaker
        )
        meetings.appendSegment(id: id, segment: segment)
        if speaker == "You" {
            activeMeetingPartialYou = ""
            lastYouSpeechAt = .now
            activeMeetingChannel = .you
        } else {
            activeMeetingPartialOthers = ""
            lastOthersSpeechAt = .now
            activeMeetingChannel = .others
        }
        refreshMeetingPartialDisplay()
    }

    private func refreshMeetingPartialDisplay() {
        let remoteLabel = remoteSpeakerLabel
        let parts = [activeMeetingPartialYou, activeMeetingPartialOthers]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        partialText = parts.joined(separator: " · ")
        if let id = activeMeetingID {
            let base = meetings.notes.first(where: { $0.id == id })?.labeledTranscript ?? ""
            let live = [
                activeMeetingPartialYou.isEmpty ? nil : "[You] \(activeMeetingPartialYou)",
                activeMeetingPartialOthers.isEmpty ? nil : "[\(remoteLabel)] \(activeMeetingPartialOthers)"
            ].compactMap { $0 }.joined(separator: "\n")
            let combined = [base, live].filter { !$0.isEmpty }.joined(separator: "\n")
            meetings.updateTranscript(id: id, transcript: combined)
        }
    }

    private func noteChannelActivity(youLevel: Float?, othersLevel: Float?) {
        let threshold: Float = 0.12
        if let youLevel, youLevel >= threshold {
            lastYouSpeechAt = .now
        }
        if let othersLevel, othersLevel >= threshold {
            lastOthersSpeechAt = .now
        }
        let youRecent = lastYouSpeechAt.map { Date().timeIntervalSince($0) < 0.7 } ?? false
        let othersRecent = lastOthersSpeechAt.map { Date().timeIntervalSince($0) < 0.7 } ?? false
        if youRecent && othersRecent {
            // Prefer the louder channel when both are hot.
            activeMeetingChannel = (youLevel ?? audioLevel) >= (othersLevel ?? remoteAudioLevel)
                ? .you : .others
        } else if youRecent {
            activeMeetingChannel = .you
        } else if othersRecent {
            activeMeetingChannel = .others
        } else if (youLevel ?? 0) < threshold && (othersLevel ?? 0) < threshold {
            activeMeetingChannel = nil
        }
    }

    private func startRosterPolling() {
        stopRosterPolling()
        rosterPollTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.phase == .meetingRecording {
                let roster = MeetingParticipantReader.readRoster(
                    preferredAppName: self.recordingMeetingAppName ?? self.detectedMeeting?.appName,
                    preferredBundleID: self.detectedMeeting?.bundleID
                )
                if !roster.names.isEmpty {
                    self.liveParticipantRoster = roster.names
                    if let id = self.activeMeetingID {
                        self.meetings.updateParticipantRoster(id: id, names: roster.names)
                    }
                }
                try? await Task.sleep(for: .seconds(8))
            }
        }
    }

    private func stopRosterPolling() {
        rosterPollTask?.cancel()
        rosterPollTask = nil
    }

    /// Rename-once: apply a speaker label across the whole transcript and lock it.
    func renameMeetingSpeaker(noteID: UUID, from: String, to: String) {
        meetings.renameSpeaker(id: noteID, from: from, to: to)
    }

    private func meetingHints(attendees: [String]) -> [String] {
        let spellings = Array(dictionary.preferredSpellings.prefix(40))
        let incorrects = dictionary.entries.map(\.incorrect)
        let recent = history.recentVocabulary(limit: 30)
        return Array((attendees + spellings + incorrects + recent).uniqued().prefix(100))
    }

    private func selectedMeetingFocus(_ id: UUID) {
        highlightedMeetingID = id
    }

    func refreshUpcomingCalendar() {
        upcomingCalendarMeeting = calendar.currentOrUpcoming()
    }

    func requestCalendarAccess() async {
        _ = await calendar.requestAccess()
        refreshUpcomingCalendar()
        await refreshUpcomingBriefIfNeeded()
    }

    func refreshUpcomingBriefIfNeeded() async {
        refreshUpcomingCalendar()
        guard let cal = upcomingCalendarMeeting else {
            upcomingBrief = nil
            return
        }
        upcomingBrief = await meetingIntelligence.brief(
            calendar: cal,
            pastNotes: meetings.notes
        )
    }

    func catchUpOnActiveMeeting() {
        guard let id = activeMeetingID,
              let note = meetings.notes.first(where: { $0.id == id })
        else {
            meetingCatchUp = "Start a meeting to catch up."
            return
        }
        let since = lastCatchUpOffset
        lastCatchUpOffset = note.segments.last.map(\.startOffset) ?? since
        Task {
            let text = await meetingIntelligence.catchUp(
                segments: note.segments,
                sinceOffset: since,
                attendees: note.attendees
            )
            meetingCatchUp = text
            meetings.updateCatchUp(id: id, text: text)
        }
    }

    func askMeetings(question: String) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        meetingAskBusy = true
        meetingAskAnswer = nil
        Task {
            let answer = await meetingIntelligence.ask(question: q, notes: meetings.notes)
            meetingAskAnswer = answer
            meetingAskBusy = false
        }
    }

    func revealAgentExportFolder() {
        NSWorkspace.shared.open(MeetingAgentExport.rootDirectory)
    }

    private func updateActiveMeetingTranscript(_ text: String) {
        guard let id = activeMeetingID else { return }
        meetings.updateTranscript(id: id, transcript: text)
    }

    private func dictionaryHints() -> [String] {
        let spellings = Array(dictionary.preferredSpellings.prefix(40))
        let incorrects = dictionary.entries.map(\.incorrect)
        let recent = history.recentVocabulary(limit: 40)
        // Prefer correct spellings as ASR context; include incorrects + recent vocab.
        return Array((spellings + incorrects + recent).uniqued().prefix(80))
    }

    func toggleListeningPillCollapsed() {
        listeningPillCollapsed.toggle()
        updateListeningPillPanel()
    }

    func collapseListeningPill() {
        guard !listeningPillCollapsed else { return }
        listeningPillCollapsed = true
        updateListeningPillPanel()
    }

    func expandListeningPill() {
        guard listeningPillCollapsed else { return }
        listeningPillCollapsed = false
        updateListeningPillPanel()
    }

    func listeningPillOrigin() -> CGPoint {
        listeningPill?.frame.origin ?? .zero
    }

    func moveListeningPill(to origin: CGPoint) {
        listeningPill?.setFrameOrigin(origin)
    }

    func flowSidebarOrigin() -> CGPoint {
        meetingPromptPanel?.frame.origin ?? .zero
    }

    func moveFlowSidebar(to origin: CGPoint) {
        meetingPromptPanel?.setFrameOrigin(origin)
    }

    // MARK: - Pill UI

    private func showListeningPill(_ visible: Bool) {
        if visible {
            // Fresh session starts expanded so live transcript is visible.
            if listeningPill?.isVisible != true {
                listeningPillCollapsed = false
            }
            updateListeningPillPanel()
            listeningPill?.orderFrontRegardless()
        } else {
            listeningPillCollapsed = false
            listeningPill?.orderOut(nil)
        }
    }

    private func updateListeningPillPanel() {
        let collapsed = listeningPillCollapsed
        // Includes SwiftUI padding so the shape shadow isn't clipped.
        let size = collapsed
            ? CGSize(width: 92, height: 80)
            : CGSize(width: 420, height: 92)

        if listeningPill == nil {
            let panel = makeFloatingPanel(size: size, level: .floating)
            panel.contentViewController = ClearHostingController(rootView: ListeningPillView(model: self))
            listeningPill = panel

            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                panel.setFrameOrigin(
                    NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 28)
                )
            }
        } else if let host = listeningPill?.contentViewController as? NSHostingController<ListeningPillView> {
            host.rootView = ListeningPillView(model: self)
        }

        guard let panel = listeningPill else { return }

        let oldFrame = panel.frame
        // Keep the pill centered horizontally when collapsing/expanding.
        let newOrigin = NSPoint(
            x: oldFrame.midX - size.width / 2,
            y: oldFrame.minY
        )
        panel.setFrame(NSRect(origin: newOrigin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    private func updateFlowSidebarPanel() {
        let expanded = (showMeetingPrompt && !meetingPromptMinimized) || flowSidebarExpanded
        // Includes SwiftUI padding so the shape shadow isn't clipped.
        let size = expanded
            ? CGSize(width: 336, height: showMeetingPrompt ? 224 : 176)
            : CGSize(width: 72, height: 140)

        if meetingPromptPanel == nil {
            let panel = makeFloatingPanel(size: size, level: .statusBar)
            panel.contentViewController = ClearHostingController(rootView: MeetingPromptView(model: self))
            meetingPromptPanel = panel

            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                panel.setFrameOrigin(
                    NSPoint(
                        x: frame.maxX - size.width - 12,
                        y: frame.midY - size.height / 2
                    )
                )
            }
        } else if let host = meetingPromptPanel?.contentViewController as? NSHostingController<MeetingPromptView> {
            host.rootView = MeetingPromptView(model: self)
        }

        guard let panel = meetingPromptPanel else { return }

        // Resize while keeping the trailing edge anchored so expand/collapse doesn't jump.
        let oldFrame = panel.frame
        let newOrigin = NSPoint(
            x: oldFrame.maxX - size.width,
            y: oldFrame.midY - size.height / 2
        )
        panel.setFrame(NSRect(origin: newOrigin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    /// Borderless transparent panel — window shadow stays off so we don't get a
    /// rectangular halo; the SwiftUI views draw their own shape-matched shadow.
    private func makeFloatingPanel(size: CGSize, level: NSWindow.Level) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = level
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isOpaque = false
        // SwiftUI hosting views eat background drags — views use WindowDragHandle /
        // draggablePanel instead. Keeping this false avoids a false sense of support.
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }
}
