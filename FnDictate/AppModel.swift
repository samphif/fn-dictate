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
    var statusMessage = "Hold Fn to dictate"
    var showOnboarding = false
    var showNotes = false
    var lastError: String?
    var includeSystemAudioInMeetings = false
    var activeMeetingID: UUID?

    let permissions = PermissionManager()
    let history = HistoryStore()
    let meetings = MeetingStore()

    private let fnMonitor = FnKeyMonitor()
    private let mic = MicrophoneCapture()
    private let cleaner = TextCleaner()
    private var speech: SpeechTranscriptionService?
    private var systemAudio: SystemAudioCapture?
    private var listeningPill: NSPanel?
    private var didBootstrap = false

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true

        permissions.refresh()
        showOnboarding = !permissions.allRequiredGranted

        if #available(macOS 26, *) {
            speech = SpeechTranscriptionService()
        }

        Task {
            await cleaner.prewarm()
            if let speech {
                try? await speech.prewarm()
            }
        }

        startHotkeysIfPossible()
    }

    func startHotkeysIfPossible() {
        permissions.refresh()
        guard permissions.accessibilityTrusted else { return }

        fnMonitor.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleHotkey(event)
            }
        }

        do {
            try fnMonitor.start()
            statusMessage = "Hold Fn (or Ctrl+Opt) to dictate"
        } catch {
            lastError = "Could not start Fn key monitor. Grant Input Monitoring, then relaunch."
            permissions.promptInputMonitoring()
        }
    }

    func refreshPermissionsAndMaybeStart() {
        permissions.refresh()
        if permissions.allRequiredGranted {
            showOnboarding = false
            startHotkeysIfPossible()
        }
    }

    private func handleHotkey(_ event: FnKeyMonitor.Event) {
        switch event {
        case .holdBegan:
            guard phase == .idle else { return }
            Task { await beginDictation() }
        case .holdEnded:
            guard phase == .listening else { return }
            Task { await endDictation(cancel: false) }
        case .cancel:
            if phase == .listening {
                Task { await endDictation(cancel: true) }
            }
        }
    }

    private func beginDictation() async {
        permissions.refresh()
        guard permissions.microphoneGranted else {
            lastError = "Microphone permission required."
            showOnboarding = true
            return
        }
        guard let speech else {
            lastError = "SpeechAnalyzer requires macOS 26+."
            return
        }

        phase = .listening
        partialText = ""
        statusMessage = "Listening…"
        showListeningPill(true)

        do {
            await speech.setPartialHandler { [weak self] text in
                Task { @MainActor in
                    self?.partialText = text
                }
            }
            try await speech.startSession()
            mic.onBuffer = { buffer in
                let packet = SendablePCMBuffer(buffer: buffer)
                Task {
                    await speech.append(packet)
                }
            }
            try mic.start()
        } catch {
            lastError = error.localizedDescription
            mic.stop()
            await speech.cancel()
            phase = .idle
            statusMessage = "Hold Fn to dictate"
            showListeningPill(false)
        }
    }

    private func endDictation(cancel: Bool) async {
        mic.stop()
        showListeningPill(false)

        guard let speech else {
            phase = .idle
            return
        }

        if cancel {
            await speech.cancel()
            partialText = ""
            phase = .idle
            statusMessage = "Cancelled"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.statusMessage = "Hold Fn to dictate"
            }
            return
        }

        phase = .processing
        statusMessage = "Transcribing…"
        let raw = await speech.finish()
        let (bundleID, name) = TextPaster.frontmostApp()
        let tone = CleanupTone.forApp(bundleID: bundleID, name: name)
        statusMessage = "Cleaning up…"
        let cleaned = await cleaner.clean(raw, tone: tone)

        if !cleaned.isEmpty {
            TextPaster.paste(cleaned)
            history.add(TranscriptEntry(text: cleaned, appName: name))
            statusMessage = "Pasted"
            partialText = cleaned
        } else {
            statusMessage = "No speech detected"
        }

        phase = .idle
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard self?.phase == .idle else { return }
            self?.statusMessage = "Hold Fn to dictate"
            self?.partialText = ""
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
            lastError = "Microphone permission required for meetings."
            showOnboarding = true
            return
        }
        guard let speech else {
            lastError = "SpeechAnalyzer requires macOS 26+."
            return
        }

        var note = MeetingNote(
            title: "Meeting \(Date().formatted(date: .abbreviated, time: .shortened))",
            includeSystemAudio: includeSystemAudioInMeetings
        )
        meetings.upsert(note)
        activeMeetingID = note.id

        phase = .meetingRecording
        statusMessage = "Recording meeting…"
        partialText = ""
        showListeningPill(true)

        do {
            await speech.setPartialHandler { [weak self] text in
                Task { @MainActor in
                    self?.partialText = text
                    self?.updateActiveMeetingTranscript(text)
                }
            }
            try await speech.startSession()

            mic.onBuffer = { buffer in
                let packet = SendablePCMBuffer(buffer: buffer)
                Task { await speech.append(packet) }
            }
            try mic.start()

            if includeSystemAudioInMeetings {
                let capture = SystemAudioCapture()
                capture.onBuffer = { buffer in
                    let packet = SendablePCMBuffer(buffer: buffer)
                    Task { await speech.append(packet) }
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
        statusMessage = "Summarizing meeting…"
        mic.stop()
        let capture = systemAudio
        systemAudio = nil
        if let capture {
            await capture.stop()
        }
        showListeningPill(false)

        let transcript: String
        if let speech {
            transcript = await speech.finish()
        } else {
            transcript = partialText
        }

        var note = await cleaner.summarizeMeeting(transcript: transcript)
        if let id = activeMeetingID, let existing = meetings.notes.first(where: { $0.id == id }) {
            note = MeetingNote(
                id: existing.id,
                title: note.title.isEmpty ? existing.title : note.title,
                createdAt: existing.createdAt,
                endedAt: .now,
                transcript: note.transcript,
                summary: note.summary,
                decisions: note.decisions,
                actionItems: note.actionItems,
                openQuestions: note.openQuestions,
                includeSystemAudio: existing.includeSystemAudio
            )
        } else {
            note.endedAt = .now
        }

        meetings.upsert(note)
        activeMeetingID = nil
        showNotes = true
        phase = .idle
        statusMessage = "Meeting saved"
        partialText = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard self?.phase == .idle else { return }
            self?.statusMessage = "Hold Fn to dictate"
        }
    }

    private func cancelMeetingRecording() async {
        mic.stop()
        let capture = systemAudio
        systemAudio = nil
        if let capture {
            await capture.stop()
        }
        if let speech {
            await speech.cancel()
        }
        showListeningPill(false)
        activeMeetingID = nil
        phase = .idle
        statusMessage = "Hold Fn to dictate"
    }

    private func updateActiveMeetingTranscript(_ text: String) {
        guard let id = activeMeetingID else { return }
        meetings.updateTranscript(id: id, transcript: text)
    }

    // MARK: - Pill UI

    private func showListeningPill(_ visible: Bool) {
        if visible {
            if listeningPill == nil {
                let panel = NSPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 320, height: 56),
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
            }
            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                let size = listeningPill?.frame.size ?? CGSize(width: 320, height: 56)
                listeningPill?.setFrameOrigin(
                    NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 28)
                )
            }
            listeningPill?.orderFrontRegardless()
        } else {
            listeningPill?.orderOut(nil)
        }
    }
}
