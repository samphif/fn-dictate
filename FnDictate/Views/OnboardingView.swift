import AppKit
import SwiftUI

struct OnboardingView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var continueHint: String?

    private var canContinue: Bool {
        model.permissions.allRequiredGranted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 28)

            VStack(spacing: 10) {
                permissionRow(
                    title: "Microphone",
                    detail: "Needed to capture your voice",
                    systemImage: "mic.fill",
                    granted: model.permissions.microphoneGranted,
                    actionTitle: "Allow",
                    action: {
                        Task { await model.permissions.requestMicrophone() }
                    },
                    settings: { model.permissions.openMicrophoneSettings() }
                )

                permissionRow(
                    title: "Accessibility",
                    detail: "Needed to paste dictated text",
                    systemImage: "accessibility",
                    granted: model.permissions.accessibilityTrusted,
                    actionTitle: "Prompt",
                    action: { model.permissions.promptAccessibility() },
                    settings: { model.permissions.openAccessibilitySettings() }
                )
            }
            .padding(.bottom, 24)

            conflictTips
                .padding(.bottom, 20)

            Text("After enabling a permission in Settings, return here — or quit Fn Dictate and relaunch if a checkmark doesn’t appear. Choose Not now to skip this screen on future launches; reopen anytime from the menu.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)

            if let continueHint {
                Text(continueHint)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
            }

            HStack {
                Button("Not now") {
                    model.completeSetup()
                    closeSetupWindow()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Spacer(minLength: 0)

                Button("Continue") {
                    finishOnboarding()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canContinue)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(width: 520)
        .onAppear { model.permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.permissions.refresh()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 48, height: 48)
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Fn Dictate")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Hold Fn to dictate into Cursor, Edge, or any app. Meetings get local summaries.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var conflictTips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Avoid conflicts", systemImage: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

            VStack(alignment: .leading, spacing: 8) {
                tipRow("Quit Wispr Flow if it’s installed")
                tipRow("Remove BetterTouchTool remaps of the Fn / Globe key")
                tipRow("Turn off macOS Dictation’s Fn shortcut in Keyboard settings")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func tipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func finishOnboarding() {
        model.refreshPermissionsAndMaybeStart()
        if model.permissions.allRequiredGranted {
            continueHint = nil
            model.completeSetup()
            closeSetupWindow()
        } else {
            continueHint = missingPermissionHint()
        }
    }

    private func missingPermissionHint() -> String {
        var missing: [String] = []
        if !model.permissions.microphoneGranted { missing.append("Microphone") }
        if !model.permissions.accessibilityTrusted { missing.append("Accessibility") }
        guard !missing.isEmpty else {
            return "Permissions still pending — quit Fn Dictate and relaunch after enabling them in Settings."
        }
        return "Still needed: \(missing.joined(separator: ", ")). Enable in Settings, then quit & relaunch."
    }

    private func closeSetupWindow() {
        dismiss()
        // Fallback when dismiss() is a no-op (e.g. MenuBarExtra-hosted scenes).
        for window in NSApp.windows where window.title == "Setup" {
            window.close()
        }
    }

    private func permissionRow(
        title: String,
        detail: String,
        systemImage: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping () -> Void,
        settings: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(granted ? Color.green.opacity(0.18) : Color.primary.opacity(0.08))
                    .frame(width: 36, height: 36)
                Image(systemName: granted ? "checkmark" : systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(granted ? .green : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if granted {
                Text("Enabled")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.12), in: Capsule())
            } else {
                HStack(spacing: 8) {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .frame(minWidth: 72)

                    Button("Settings", action: settings)
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .frame(minWidth: 72)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
