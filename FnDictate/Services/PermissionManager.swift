import ApplicationServices
import AVFoundation
import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class PermissionManager {
    var microphoneGranted = false
    var accessibilityTrusted = false
    var inputMonitoringTrusted = false

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
        inputMonitoringTrusted = CGPreflightListenEventAccess()
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

    func promptInputMonitoring() {
        inputMonitoringTrusted = CGRequestListenEventAccess()
    }

    func openAccessibilitySettings() {
        openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openMicrophoneSettings() {
        openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    func openInputMonitoringSettings() {
        openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    func openScreenRecordingSettings() {
        openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
