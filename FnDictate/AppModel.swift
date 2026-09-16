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
    var activeMeetingID: UUID?
    var detectedMeeting: DetectedMeeting?
    var showMeetingPrompt = false
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

    /// True when dictation was started via double-tap (stays on until tap/Esc).
    private var handsFreeDictation = false
    /// App that had focus when dictation started — restored before paste.
    @ObservationIgnored private var dictationTargetApp: NSRunningApplication?
    private var toneOverrides: [String: String] = [:]
    private let toneOverridesKey = "FnDictate.toneOverrides"
    private let didMineHistoryKey = "FnDictate.didMineHistoryForDictionary"
    private let setupCompletedKey = "FnDictate.setupCompleted"
    private let learnFromInAppKey = "FnDictate.learnFromInAppCorrections"

    let permissions = PermissionManager()
    let history = HistoryStore()
    let meetings = MeetingStore()
    let dictionary = DictionaryStore()
    let calendar = CalendarMeetingService()

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
            $0.title == "Library" || $0.identifier?.rawValue == "library"
        }) {
            libraryWindow = existing
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
        window.title = "Library"
        window.setContentSize(NSSize(width: 1120, height: 720))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setFrameAutosaveName("FnDictate.Library")
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        libraryWindow = window
    }

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true

        loadToneOverrides()
        if UserDefaults.standard.object(forKey: learnFromInAppKey) == nil {
            learnFromInAppCorrections = true
        } else {
            learnFromInAppCorrections = UserDefaults.standard.bool(forKey: learnFromInAppKey)
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
        refreshCurrentTone()
    }

    /// Cycles Raw → Light → Polished for the frontmost app and persists the override.
    func cycleTone() {
        let (bundleID, _) = TextPaster.frontmostApp()
        let next = currentTone.next
        if let bundleID, !bundleID.isEmpty {
            toneOverrides[bundleID] = next.rawValue
            saveToneOverrides()
        }
        currentTone = next
    }

    private func refreshCurrentTone() {
        let (bundleID, name) = TextPaster.frontmostApp()
        currentTone = effectiveTone(bundleID: bundleID, name: name)
    }

    private func effectiveTone(bundleID: String?, name: String?) -> CleanupTone {
        if let bundleID,
           let raw = toneOverrides[bundleID],
           let override = CleanupTone(rawValue: raw)
        {
            return override
        }
        return CleanupTone.forApp(bundleID: bundleID, name: name)
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
        meetingDetector.onMeetingEnded = { [weak self] in
            Task { @MainActor in
                self?.handleMeetingDetectionEnded()
            }
        }
        meetingDetector.start()
    }

    private func handleMeetingDetected(_ meeting: DetectedMeeting) {
        detectedMeeting = meeting
        // Don't interrupt active work with the prompt.
        guard phase == .idle else { return }
        showMeetingPrompt = true
        showMeetingPromptPanel(true)
    }

    private func handleMeetingDetectionEnded() {
        detectedMeeting = nil
        if showMeetingPrompt {
            showMeetingPrompt = false
            showMeetingPromptPanel(false)
        }
    }

    func dismissMeetingPrompt() {
        meetingDetector.dismissCurrent()
        showMeetingPrompt = false
        showMeetingPromptPanel(false)
    }

    func acceptDetectedMeeting() {
        includeSystemAudioInMeetings = true
        showMeetingPrompt = false
        showMeetingPromptPanel(false)
        toggleMeeting()
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
            historyEntryID: historyEntryID
        ) { [weak self] result in
            guard let self else { return }
            self.handleInAppCorrection(pasted: pasted, result: result)
        }
    }

    private func handleInAppCorrection(pasted: String, result: InAppCorrectionWatcher.Result) {
        let corrected = result.correctedPaste
        guard corrected != pasted else { return }

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
        meetingStartedAt = .now

        refreshUpcomingCalendar()
        let cal = upcomingCalendarMeeting
        let title = cal?.title
            ?? "Meeting \(Date().formatted(date: .abbreviated, time: .shortened))"
        let attendees = cal?.attendees ?? []

        var note = MeetingNote(
            title: title,
            includeSystemAudio: includeSystemAudioInMeetings,
            attendees: attendees,
            calendarEventIdentifier: cal?.eventIdentifier,
            calendarTitle: cal?.title,
            brief: upcomingBrief
        )
        meetings.upsert(note)
        activeMeetingID = note.id
        selectedMeetingFocus(note.id)

        phase = .meetingRecording
        statusMessage = "Recording meeting…"
        partialText = ""
        showListeningPill(true)
        requestedLibraryTab = .meetings
        showLibrary = true
        presentLibraryWindow()

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
                }
            }
            try mic.start()

            if includeSystemAudioInMeetings {
                let remote = speechRemote ?? speech
                if remote !== speech {
                    await remote.setPartialHandler { [weak self] text in
                        Task { @MainActor in
                            self?.activeMeetingPartialOthers = text
                            self?.refreshMeetingPartialDisplay()
                        }
                    }
                    await remote.setFinalSegmentHandler { [weak self] text, offset in
                        Task { @MainActor in
                            self?.appendMeetingSegment(text: text, offset: offset, speaker: "Others")
                        }
                    }
                    try await remote.startSession(contextualStrings: hints)
                }

                let capture = SystemAudioCapture()
                capture.onBuffer = { buffer in
                    let packet = SendablePCMBuffer(buffer: buffer)
                    Task { await remote.append(packet) }
                }
                do {
                    try await capture.start()
                    systemAudio = capture
                } catch {
                    lastError = "System audio unavailable (\(error.localizedDescription)). Continuing with microphone only."
                    permissions.openScreenRecordingSettings()
                }
            }
        } catch {
            lastError = error.localizedDescription
            await cancelMeetingRecording()
        }
    }

    private func stopMeeting() async {
        phase = .meetingProcessing
        statusMessage = "Re-reading meeting…"
        mic.stop()
        audioLevel = 0
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
        // Ensure any leftover finals that didn't fire as segments still land in transcript.
        if note.segments.isEmpty {
            var segs: [MeetingTranscriptSegment] = []
            if !youText.isEmpty {
                segs.append(MeetingTranscriptSegment(startOffset: 0, text: youText, speaker: "You"))
            }
            if !othersText.isEmpty {
                segs.append(MeetingTranscriptSegment(startOffset: 0.1, text: othersText, speaker: "Others"))
            }
            note.segments = segs
        }

        let rawLabeled = note.labeledTranscript.isEmpty
            ? [youText, othersText].filter { !$0.isEmpty }.joined(separator: "\n")
            : note.labeledTranscript
        let withDictionary = dictionary.apply(to: rawLabeled)

        let refined = await meetingIntelligence.refine(
            transcript: withDictionary,
            segments: note.segments,
            attendees: note.attendees,
            calendarTitle: note.calendarTitle,
            dictionaryHints: Array(dictionary.preferredSpellings.prefix(40))
        )

        note.title = refined.title.isEmpty ? note.title : refined.title
        note.endedAt = .now
        note.transcript = refined.transcript.isEmpty ? withDictionary : refined.transcript
        note.summary = refined.summary
        note.decisions = refined.decisions
        note.actionItems = refined.actionItems
        note.openQuestions = refined.openQuestions
        if !refined.segments.isEmpty {
            note.segments = refined.segments
        }
        note.transcript = dictionary.apply(to: note.transcript)

        meetings.upsert(note)
        activeMeetingID = nil
        meetingStartedAt = nil
        highlightedMeetingID = note.id
        requestedLibraryTab = .meetings
        showLibrary = true
        presentLibraryWindow()
        phase = .idle
        statusMessage = "Meeting saved"
        partialText = ""
        activeMeetingPartialYou = ""
        activeMeetingPartialOthers = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard self?.phase == .idle else { return }
            self?.statusMessage = "Hold Fn · double-tap hands-free"
        }
    }

    private func cancelMeetingRecording() async {
        mic.stop()
        audioLevel = 0
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
        } else {
            activeMeetingPartialOthers = ""
        }
        refreshMeetingPartialDisplay()
    }

    private func refreshMeetingPartialDisplay() {
        let parts = [activeMeetingPartialYou, activeMeetingPartialOthers]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        partialText = parts.joined(separator: " · ")
        if let id = activeMeetingID {
            let base = meetings.notes.first(where: { $0.id == id })?.labeledTranscript ?? ""
            let live = [
                activeMeetingPartialYou.isEmpty ? nil : "[You] \(activeMeetingPartialYou)",
                activeMeetingPartialOthers.isEmpty ? nil : "[Others] \(activeMeetingPartialOthers)"
            ].compactMap { $0 }.joined(separator: "\n")
            let combined = [base, live].filter { !$0.isEmpty }.joined(separator: "\n")
            meetings.updateTranscript(id: id, transcript: combined)
        }
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

    // MARK: - Pill UI

    private func showListeningPill(_ visible: Bool) {
        if visible {
            if listeningPill == nil {
                let panel = NSPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 400, height: 68),
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                panel.isFloatingPanel = true
                panel.level = .floating
                panel.backgroundColor = .clear
                panel.hasShadow = true
                panel.isOpaque = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel.contentViewController = NSHostingController(rootView: ListeningPillView(model: self))
                listeningPill = panel
            } else if let host = listeningPill?.contentViewController as? NSHostingController<ListeningPillView> {
                host.rootView = ListeningPillView(model: self)
            }
            let pillHeight: CGFloat = 68
            listeningPill?.setContentSize(NSSize(width: 400, height: pillHeight))
            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                let size = listeningPill?.frame.size ?? CGSize(width: 400, height: pillHeight)
                listeningPill?.setFrameOrigin(
                    NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 28)
                )
            }
            listeningPill?.orderFrontRegardless()
        } else {
            listeningPill?.orderOut(nil)
        }
    }

    private func showMeetingPromptPanel(_ visible: Bool) {
        if visible {
            if meetingPromptPanel == nil {
                let panel = NSPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 332, height: 180),
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                panel.isFloatingPanel = true
                panel.level = .statusBar
                panel.backgroundColor = .clear
                panel.hasShadow = true
                panel.isOpaque = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel.contentViewController = NSHostingController(rootView: MeetingPromptView(model: self))
                meetingPromptPanel = panel
            }
            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                let size = meetingPromptPanel?.frame.size ?? CGSize(width: 332, height: 180)
                meetingPromptPanel?.setFrameOrigin(
                    NSPoint(x: frame.maxX - size.width - 20, y: frame.midY - size.height / 2)
                )
            }
            meetingPromptPanel?.orderFrontRegardless()
        } else {
            meetingPromptPanel?.orderOut(nil)
        }
    }
}
