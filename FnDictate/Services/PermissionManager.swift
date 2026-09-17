import ApplicationServices
import AVFoundation
import AppKit
import CoreGraphics
import Foundation
import Observation
import ScreenCaptureKit

@MainActor
@Observable
final class PermissionManager {
    var microphoneGranted = false
    var accessibilityTrusted = false
    /// Screen Recording — required for meeting system-audio (Others) capture.
    var screenRecordingGranted = false

    /// Mic + Accessibility are enough (Fn via NSEvent; paste via synthetic ⌘V).
    var allRequiredGranted: Bool {
        microphoneGranted && accessibilityTrusted
    }

    func refresh() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneGranted = true
        default:
            microphoneGranted = false
        }

        accessibilityTrusted = AXIsProcessTrusted()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
    }

    func requestMicrophone() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneGranted = granted
    }

    func promptAccessibility() {
        // Avoid concurrency warning on the global CFString constant.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
    }

    /// Triggers the system Screen Recording prompt when possible.
    /// After the user enables access in Settings, macOS usually requires a relaunch.
    @discardableResult
    func requestScreenRecording() async -> Bool {
        // Prefer the CoreGraphics request API — it shows the system sheet when needed.
        if CGRequestScreenCaptureAccess() {
            screenRecordingGranted = true
            return true
        }

        // Fallback: touching shareable content also exercises the TCC path.
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            screenRecordingGranted = true
            return true
        } catch {
            screenRecordingGranted = CGPreflightScreenCaptureAccess()
            return screenRecordingGranted
        }
    }

    func openAccessibilitySettings() {
        openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openMicrophoneSettings() {
        openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    func openScreenRecordingSettings() {
        // Opens Privacy → Screen & System Audio Recording on modern macOS.
        openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
